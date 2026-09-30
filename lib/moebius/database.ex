defmodule Moebius.Database do
  @moduledoc """
  Turns a module into a database you can run commands against.

  ```elixir
  defmodule MyApp.Db do
    use Moebius.Database
  end

  # in your application's supervision tree
  children = [
    {MyApp.Db, Moebius.get_connection()}
  ]
  ```

  Each database module owns a pool of connections, started as one child of your tree. If
  Postgres goes away, the pool keeps running and calls return `{:error, message}` until it
  comes back. Nothing else in your tree restarts.

  ## Connection options

  * `:url` - `postgres://user:pass@host:port/database`, or the separate `:hostname`, `:port`,
    `:database`, `:username`, `:password`. A missing username or password falls back to
    `PGUSER` / `PGPASSWORD`.
  * `:socket_dir` - connect over a Unix socket in this directory instead of TCP.
  * `:ssl` - `true` (use TLS if the server offers it) or `:required`, with `:ssl_opts`.
  * `:pool_size` - the most connections the pool opens (default 10).
  * `:pool_min` - connections opened at start and kept when idle (default: `pool_size`, so
    the pool is full from the start). Set it lower to let an idle pool shrink.
  * `:checkout_timeout` - how long a call waits for a free connection, in ms (default 5000).
  * `:queue_max` - how many calls may wait for a connection at once (default 50).
  * `:max_lifetime` - recycle each connection after this many ms, for proxies and firewalls
    that drop long-lived connections.
  * `:statement_timeout`, `:lock_timeout`, `:idle_in_transaction_session_timeout` - Postgres
    settings applied to every connection, e.g. `statement_timeout: "30s"`. Setting
    `statement_timeout` is a good idea: the driver itself waits for a query forever.
  * `:settings` - any other Postgres settings, as a keyword list.
  * `:application_name` - shown in `pg_stat_activity` (default `"moebius"`).
  """

  alias Moebius.{Connection, DocumentQuery, Error, Pool, Query, Transformer}

  defmacro __using__(_opts) do
    quote location: :keep do
      @name __MODULE__

      alias Moebius.{Connection, DocumentCommand, QueryCommand, Transformer}

      @doc "Starts this database's connection pool. See `Moebius.Database` for the options."
      def start_link(opts), do: Moebius.Pool.start_link(@name, normalize_opts(opts))

      def child_spec([]), do: child_spec(Moebius.get_connection())
      def child_spec(opts), do: Moebius.Pool.child_spec(@name, normalize_opts(opts))

      # {Db, opts} and {Db, [opts]} (the form the README has always shown) both arrive here
      defp normalize_opts([opts]) when is_list(opts), do: normalize_opts(opts)

      defp normalize_opts(opts) when is_list(opts) do
        # options given explicitly win over the parts of the url
        case opts[:url] do
          nil -> opts
          url -> Keyword.merge(Moebius.parse_connection(url), opts)
        end
      end

      @doc "The pool's size and how much of it is in use."
      def pool_status, do: Moebius.Pool.status(@name)

      # ---- running SQL and commands ----

      def run(sql) when is_binary(sql), do: run(sql, [])

      def run(sql, params) when is_binary(sql) and is_list(params),
        do: run(%QueryCommand{sql: sql, params: params})

      def run(sql, %Connection{} = conn) when is_binary(sql),
        do: run(%QueryCommand{sql: sql, params: []}, conn)

      def run(sql, %Connection{} = conn, params) when is_binary(sql),
        do: run(%QueryCommand{sql: sql, params: params}, conn)

      def run(%QueryCommand{} = cmd), do: cmd |> execute() |> Moebius.Database.shape(cmd)

      def run(%DocumentCommand{} = cmd),
        do:
          cmd
          |> Moebius.Database.document_select()
          |> execute_document()
          |> Transformer.from_json()

      def run(%QueryCommand{} = cmd, %Connection{} = conn),
        do: cmd |> Moebius.Database.execute(conn) |> Moebius.Database.shape(cmd)

      defdelegate all(table), to: __MODULE__, as: :run

      def first(%DocumentCommand{} = cmd) do
        cmd
        |> Moebius.Database.document_select()
        |> execute_document()
        |> Transformer.from_json(:single)
      end

      def first(%QueryCommand{sql: nil} = cmd),
        do: cmd |> Moebius.Query.select() |> execute() |> Transformer.to_single()

      def first(%QueryCommand{} = cmd), do: cmd |> execute() |> Transformer.to_single()

      defdelegate one(table), to: __MODULE__, as: :first

      def find(%QueryCommand{} = cmd, id) do
        %{
          cmd
          | sql: "select * from #{cmd.table_name} where id = $1",
            params: [Moebius.Database.id(id)]
        }
        |> execute()
        |> Transformer.to_single()
      end

      def find(%DocumentCommand{} = cmd, id) do
        cmd
        |> Moebius.DocumentQuery.find(Moebius.Database.id(id))
        |> execute_document()
        |> Transformer.from_json(:single)
      end

      @doc """
      Streams the rows of a query or document query through a server-side cursor, so large
      results never sit in memory at once. Read it in the process that created it.

      * `:chunk` - rows fetched per round-trip (default 500).

      ```elixir
      db(:events) |> sort(:id) |> MyApp.Db.stream() |> Stream.each(&handle/1) |> Stream.run()
      ```
      """
      def stream(cmd, opts \\ []) do
        chunk = Keyword.get(opts, :chunk, 500)

        unless is_integer(chunk) and chunk > 0,
          do: raise(ArgumentError, ":chunk must be a positive integer, got: #{inspect(chunk)}")

        Moebius.Database.stream(@name, cmd, chunk)
      end

      @doc """
      Asks Postgres how it will run a query, and returns the plan as text.

      * `:analyze` - also run the query and report real timings and row counts. The query runs
        inside a transaction that is rolled back, so writes are not kept.
      """
      def explain(cmd, opts \\ []), do: Moebius.Database.explain(@name, cmd, opts)

      @doc """
      Bulk loads rows into a table with Postgres's `COPY` protocol, the fastest way to write
      many rows. Returns `{:ok, count}` or `{:error, message}`; if any row fails, none are
      written.

      `rows` is any Enumerable of keyword lists or maps, including a lazy `Stream`, which is
      sent in chunks so memory stays flat however many rows there are. The columns are the
      keys of the first row, unless you pass `:columns`.

      * `:columns` - the columns to fill, in order.
      * `:chunk` - rows sent per message to the server (default 5,000).

      ```elixir
      "events.csv"
      |> File.stream!()
      |> CSV.decode!(headers: true)
      |> Stream.map(&%{name: &1["name"], at: &1["at"]})
      |> MyApp.Db.copy(:events)
      ```
      """
      def copy(table, rows, opts \\ []), do: Moebius.Copy.copy(@name, table, rows, opts)

      # ---- batches ----

      def run_batch(%Moebius.CommandBatch{commands: commands}),
        do: Enum.map(commands, &(&1 |> execute() |> Moebius.Database.batch_result()))

      def transact_batch(%Moebius.CommandBatch{commands: commands}) do
        transaction(fn tx ->
          Enum.map(
            commands,
            &(&1 |> Moebius.Database.execute(tx) |> Moebius.Database.batch_result())
          )
        end)
      end

      # ---- transactions ----

      @doc """
      Runs `fun` in a transaction and returns what it returns.

      If a statement inside fails, or `fun` calls `rollback/1`, the transaction is rolled back
      and this returns `{:error, reason}`. If `fun` raises anything else, the transaction is
      rolled back and the exception is re-raised. A transaction inside a transaction becomes a
      savepoint, so it can fail without taking the outer one down.
      """
      def transaction(fun) when is_function(fun, 1), do: Moebius.Pool.transaction(@name, fun)

      @doc "Rolls back the current transaction, which then returns `{:error, value}`."
      defdelegate rollback(value), to: Moebius.Pool

      # ---- documents ----

      def save(%DocumentCommand{} = cmd, doc) when is_list(doc), do: save(cmd, Map.new(doc))

      def save(%DocumentCommand{} = cmd, %{__struct__: struct} = doc) do
        with {:ok, saved} <- save(cmd, Map.from_struct(doc)),
             do: {:ok, Map.put(saved, :__struct__, struct)}
      end

      def save(%DocumentCommand{} = cmd, doc) when is_map(doc),
        do: Moebius.Database.save_document(@name, cmd, doc)

      def save(%DocumentCommand{} = cmd, doc, %Connection{}) when is_map(doc) or is_list(doc),
        do: save(cmd, doc)

      def create_document_table(name) when is_atom(name) do
        with :ok <- Moebius.Database.create_document_table(@name, Moebius.DocumentQuery.db(name)),
             do: {:ok, "Table created"}
      end

      def create_document_table(%DocumentCommand{} = cmd, _doc) do
        :ok = Moebius.Database.create_document_table(@name, cmd)
        cmd
      end

      defp execute(cmd), do: Moebius.Database.execute(%{cmd | conn: @name})
      defp execute_document(cmd), do: Moebius.Database.execute_document(@name, cmd)
    end
  end

  # ---- the parts that don't need to be generated per module ----

  @doc """
  Runs a command on the connection it names (`cmd.conn` is the database module), or on the
  connection of a transaction.
  """
  def execute(%{sql: nil} = cmd), do: cmd |> Query.select() |> execute()

  def execute(%{conn: pool} = cmd) do
    Pool.checkout(pool, &query(&1, cmd))
  end

  def execute(cmd, %Connection{} = conn), do: query(conn, cmd)

  # Inside a transaction a failed statement aborts it (Postgres rejects everything after the
  # error anyway), so raise and let the transaction roll back.
  defp query(%Connection{pool: pool, pid: pid}, cmd) do
    case Connection.query(pid, cmd.sql, cmd.params) do
      {:error, %Error{} = error} ->
        if Pool.in_transaction?(pool), do: raise(error), else: {:error, error}

      ok ->
        ok
    end
  end

  @doc false
  def shape(result, %{type: type}) when type in [:insert, :update, :delete, :count],
    do: Transformer.to_single(result)

  def shape(result, _cmd), do: Transformer.to_list(result)

  @doc false
  def batch_result({:error, %Error{message: message}}), do: {:error, message}
  def batch_result(ok), do: ok

  @doc false
  # Postgres ids are integers or strings (uuid, text). Accept integer strings for integer ids,
  # which is what you get from a URL.
  def id(id) when is_binary(id) do
    if id =~ ~r/\A\d+\z/, do: String.to_integer(id), else: id
  end

  def id(id), do: id

  # ---- documents ----

  @doc false
  def document_select(%{sql: nil} = cmd), do: DocumentQuery.select(cmd)
  def document_select(cmd), do: cmd

  @doc false
  # Reading a document table that doesn't exist yet creates it (once) and tries again. Inside
  # a transaction the failed statement has already aborted it, so there the error stands;
  # call create_document_table/1 first if the table might be new.
  def execute_document(pool, cmd) do
    case execute(%{cmd | conn: pool}) do
      {:error, %Error{name: :undefined_table}} ->
        with :ok <- create_document_table(pool, cmd), do: execute(%{cmd | conn: pool})

      result ->
        result
    end
  end

  @doc false
  def save_document(pool, cmd, doc) do
    command = DocumentQuery.decide_command(%{cmd | conn: pool}, doc)

    case execute(command) do
      {:error, %Error{name: :undefined_table}} ->
        # a new table has no row to update, so an id in the document is dropped
        with :ok <- create_document_table(pool, cmd),
             do: save_document(pool, cmd, Map.delete(doc, :id))

      {:ok, _} = result ->
        with {:ok, saved} <- Transformer.from_json(result, :single),
             :ok <- update_search(pool, cmd, saved),
             do: {:ok, saved}

      {:error, %Error{message: message}} ->
        {:error, message}
    end
  end

  defp update_search(_pool, %{search_fields: []}, _saved), do: :ok

  defp update_search(pool, cmd, saved) do
    case execute(%{DocumentQuery.update_search(cmd, saved.id) | conn: pool}) do
      {:ok, _} -> :ok
      {:error, %Error{message: message}} -> {:error, message}
    end
  end

  @doc false
  # Two processes creating the same table at once can collide even with "if not exists"
  # (Postgres checks the catalog before it locks it). A transaction-scoped advisory lock on
  # the table name makes them take turns; the second one finds the table and does nothing.
  def create_document_table(pool, cmd) do
    run = fn sql, params ->
      {:ok, _} = execute(%Moebius.QueryCommand{conn: pool, sql: sql, params: params})
    end

    Pool.transaction(pool, fn _tx ->
      run.("select pg_advisory_xact_lock(hashtext($1))", [cmd.table_name])
      Enum.each(DocumentQuery.create_table_sql(cmd), &run.(&1, []))
      :ok
    end)
  end

  # ---- streams and plans ----

  @doc false
  def stream(pool, %Moebius.DocumentCommand{} = cmd, chunk) do
    cmd = document_select(cmd)
    Pool.stream(pool, cmd.sql, cmd.params, chunk, &Transformer.from_json/1)
  end

  def stream(pool, %Moebius.QueryCommand{sql: nil} = cmd, chunk),
    do: stream(pool, Query.select(cmd), chunk)

  def stream(pool, %Moebius.QueryCommand{} = cmd, chunk),
    do: Pool.stream(pool, cmd.sql, cmd.params, chunk, &Transformer.to_list/1)

  @doc false
  def explain(pool, cmd, opts) do
    cmd =
      case cmd do
        %Moebius.DocumentCommand{} -> document_select(cmd)
        %{sql: nil} -> Query.select(cmd)
        _ -> cmd
      end

    options = if opts[:analyze], do: "analyze, buffers", else: "costs"
    sql = "explain (#{options}) " <> String.trim_trailing(cmd.sql, ";")
    plan = %Moebius.QueryCommand{conn: pool, sql: sql, params: cmd.params}

    if opts[:analyze] do
      Pool.transaction(pool, fn _tx -> Pool.rollback(plan_text(execute(plan))) end)
      |> case do
        {:error, {:ok, text}} -> {:ok, text}
        {:error, {:error, message}} -> {:error, message}
        {:error, message} -> {:error, message}
      end
    else
      plan_text(execute(plan))
    end
  end

  defp plan_text({:ok, %Moebius.Result{rows: rows}}),
    do: {:ok, Enum.map_join(rows, "\n", &hd/1)}

  defp plan_text({:error, %Error{message: message}}), do: {:error, message}
end
