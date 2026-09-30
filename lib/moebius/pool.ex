defmodule Moebius.Pool do
  @moduledoc false
  # One pooler pool of epgsql connections per database module.
  #
  # Checkout rules (see the erlang-otp skill):
  #   * the process that takes a connection is the one that uses it, and it goes back in `after`
  #   * a connection whose state we can't trust goes back as :fail, and pooler replaces it
  #   * while a process holds a connection (a transaction, a stream), every query that process
  #     makes on the same pool reuses it, so plain run/1 calls join the open transaction

  alias Moebius.{Connection, Error}

  @defaults [
    pool_size: 10,
    checkout_timeout: 5_000,
    queue_max: 50
  ]

  # server settings Moebius accepts as connection options
  @settings [:statement_timeout, :lock_timeout, :idle_in_transaction_session_timeout]

  def child_spec(name, opts) do
    %{
      id: name,
      start: {__MODULE__, :start_link, [name, opts]},
      type: :supervisor
    }
  end

  def start_link(name, opts) do
    opts = Keyword.merge(@defaults, opts)
    # open every connection up front, so the first burst of traffic doesn't
    # wait on connection setup; pool_min below pool_size lets an idle pool shrink instead
    opts = Keyword.put_new(opts, :pool_min, opts[:pool_size])
    :persistent_term.put({__MODULE__, name}, %{checkout_timeout: opts[:checkout_timeout]})
    %{start: {module, fun, args}} = :pooler.pool_child_spec(config(name, opts))
    apply(module, fun, args)
  end

  @doc false
  def config(name, opts) do
    size = opts[:pool_size]

    %{
      name: name,
      init_count: min(opts[:pool_min], size),
      max_count: size,
      start_mfa: {:epgsql, :connect, [Connection.epgsql_options(opts)]},
      queue_max: opts[:queue_max],
      member_start_timeout: {10, :sec},
      cull_interval: {1, :min},
      max_age: {5, :min}
    }
    |> put_lifetime(opts[:max_lifetime])
    |> put_setup(settings(opts))
  end

  defp put_lifetime(config, nil), do: config

  defp put_lifetime(config, ms),
    do: Map.merge(config, %{max_lifetime: ms, max_lifetime_jitter: div(ms, 10)})

  defp put_setup(config, []), do: config

  defp put_setup(config, settings),
    do: Map.put(config, :initialize_mfa, {Connection, :setup, [:"$pooler_pid", settings]})

  defp settings(opts) do
    named = for key <- @settings, value = opts[key], do: {key, value}
    named ++ Keyword.get(opts, :settings, [])
  end

  @doc "Pool size and usage, from pooler."
  def status(name) do
    name |> :pooler.pool_utilization() |> Map.new()
  end

  # ---- checkout ----

  def checkout(pool, fun) do
    case Process.get({__MODULE__, :held, pool}) do
      %Connection{} = conn -> fun.(conn)
      nil -> take(pool, fun)
    end
  end

  defp take(pool, fun) do
    case take_member(pool) do
      {:ok, pid} ->
        conn = %Connection{pool: pool, pid: pid}
        Process.put({__MODULE__, :held, pool}, conn)

        try do
          fun.(conn)
        after
          Process.delete({__MODULE__, :held, pool})
          give_back(pool, pid)
        end

      {:error, _} = error ->
        error
    end
  end

  defp take_member(pool) do
    %{checkout_timeout: timeout} = :persistent_term.get({__MODULE__, pool})

    case :pooler.take_member(pool, timeout) do
      pid when is_pid(pid) ->
        {:ok, pid}

      :error_no_members ->
        {:error,
         %Error{
           name: :pool_timeout,
           message: "no connection available from #{inspect(pool)} within #{timeout}ms"
         }}
    end
  rescue
    ArgumentError -> not_started(pool)
  catch
    :exit, {:noproc, _} -> not_started(pool)
  end

  defp not_started(pool),
    do: {:error, %Error{name: :no_pool, message: "#{inspect(pool)} isn't started"}}

  defp give_back(pool, pid) do
    status = if Connection.broken?(pid), do: :fail, else: :ok
    :pooler.return_member(pool, pid, status)
  end

  def in_transaction?(pool), do: depth(pool) > 0

  # ---- transactions ----

  def transaction(pool, fun) do
    checkout(pool, fn conn ->
      case depth(pool) do
        0 -> top_level(conn, fun)
        n -> nested(conn, n, fun)
      end
    end)
  end

  @doc "Aborts the current transaction; `transaction/2` returns `{:error, value}`."
  def rollback(value), do: throw({__MODULE__, :rollback, value})

  defp top_level(conn, fun) do
    run_block(conn, fun, "begin", "commit", "rollback")
  end

  defp nested(conn, n, fun) do
    savepoint = "moebius_savepoint_#{n}"

    run_block(
      conn,
      fun,
      "savepoint #{savepoint}",
      "release savepoint #{savepoint}",
      "rollback to savepoint #{savepoint}"
    )
  end

  defp run_block(%Connection{pid: pid} = conn, fun, open, close, undo) do
    case Connection.script(pid, open) do
      :ok -> run_open_block(conn, fun, close, undo)
      {:error, error} -> {:error, error.message}
    end
  end

  defp run_open_block(%Connection{pool: pool, pid: pid} = conn, fun, close, undo) do
    set_depth(pool, depth(pool) + 1)

    try do
      result = fun.(conn)

      case finish(pid, close) do
        :ok -> result
        {:error, error} -> undo(pid, undo, error)
      end
    rescue
      error in Error ->
        undo(pid, undo, error)

      exception ->
        undo(pid, undo, nil)
        reraise exception, __STACKTRACE__
    catch
      :throw, {__MODULE__, :rollback, value} ->
        undo(pid, undo, nil)
        {:error, value}

      :throw, {:error, message} ->
        undo(pid, undo, nil)
        {:error, message}

      kind, reason ->
        undo(pid, undo, nil)
        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      set_depth(pool, depth(pool) - 1)
    end
  end

  # COMMIT on a transaction Postgres already aborted reports ROLLBACK instead of an error
  defp finish(pid, "commit") do
    with :ok <- Connection.script(pid, "commit") do
      case Connection.status(pid) do
        :rollback ->
          {:error, %Error{name: :rolled_back, message: "the transaction was rolled back"}}

        _ ->
          :ok
      end
    end
  end

  defp finish(pid, sql), do: Connection.script(pid, sql)

  defp undo(pid, sql, error) do
    case Connection.script(pid, sql) do
      :ok -> :ok
      # can't get the connection back to a known state, so don't reuse it
      {:error, _} -> Process.put({Connection, :broken, pid}, true)
    end

    if error, do: {:error, error.message}
  end

  defp depth(pool), do: Process.get({__MODULE__, :depth, pool}, 0)

  defp set_depth(pool, 0), do: Process.delete({__MODULE__, :depth, pool})
  defp set_depth(pool, n), do: Process.put({__MODULE__, :depth, pool}, n)

  # ---- streaming ----

  @doc """
  Streams the rows of a query through a server-side cursor, `chunk` rows at a time.

  The connection is held by the process that reads the stream, from the first row until the
  stream ends or is halted. Outside a transaction the cursor runs in one of its own.
  """
  def stream(pool, sql, params, chunk, transform) do
    Stream.resource(
      fn -> open_cursor(pool, sql, params) end,
      fn state -> fetch(state, chunk, transform) end,
      &close_cursor/1
    )
  end

  defp open_cursor(pool, sql, params) do
    {conn, owned?} =
      case Process.get({__MODULE__, :held, pool}) do
        %Connection{} = conn ->
          {conn, false}

        nil ->
          case take_member(pool) do
            {:ok, pid} -> {%Connection{pool: pool, pid: pid}, true}
            {:error, error} -> raise error
          end
      end

    cursor = "moebius_cursor_#{System.unique_integer([:positive])}"
    state = %{conn: conn, owned?: owned?, cursor: cursor, done?: false}

    try do
      if owned?, do: :ok = ok!(Connection.script(conn.pid, "begin"))

      sql = "declare #{cursor} no scroll cursor for #{String.trim_trailing(sql, ";")}"
      {:ok, _} = ok!(Connection.query(conn.pid, sql, params))
      state
    rescue
      error ->
        close_cursor(state)
        reraise error, __STACKTRACE__
    end
  end

  defp fetch(%{done?: true} = state, _chunk, _transform), do: {:halt, state}

  defp fetch(%{conn: conn, cursor: cursor} = state, chunk, transform) do
    {:ok, result} = ok!(Connection.query(conn.pid, "fetch #{chunk} from #{cursor}", []))

    case transform.({:ok, result}) do
      {:ok, []} -> {:halt, state}
      {:ok, rows} -> {rows, %{state | done?: length(rows) < chunk}}
    end
  end

  # our own transaction: ending it closes the cursor
  defp close_cursor(%{conn: conn, owned?: true}) do
    Connection.script(conn.pid, "commit")
    give_back(conn.pool, conn.pid)
  end

  # the caller's transaction: close the cursor and leave the transaction alone
  defp close_cursor(%{conn: conn, cursor: cursor}),
    do: Connection.script(conn.pid, "close #{cursor}")

  defp ok!({:error, %Error{} = error}), do: raise(error)
  defp ok!(ok), do: ok
end
