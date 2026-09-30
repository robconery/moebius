defmodule Moebius.Connection do
  @moduledoc """
  The handle `transaction/1` passes to your callback.

  Pass it on to `run/2`, `run/3` and `save/3` so those statements run inside the
  transaction. (Calls that leave it out also join the transaction, as long as they run in
  the same process and on the same database.)
  """

  defstruct [:pool, :pid]

  @type t :: %__MODULE__{pool: atom(), pid: pid()}

  alias Moebius.{Error, Result}

  @codecs [
    {Moebius.Codec.DateTime, []},
    {Moebius.Codec.Numeric, []},
    {:epgsql_codec_json, Moebius.Codec.JSON}
  ]

  @doc false
  # Turns Moebius connection options into the map :epgsql.connect/1 takes.
  def epgsql_options(opts) do
    port = to_port(opts[:port] || 5432)
    password = opts[:password] || System.get_env("PGPASSWORD")

    %{
      host: host(opts, port),
      port: port,
      username: opts[:username] || System.get_env("PGUSER") || "postgres",
      database: opts[:database],
      timeout: opts[:connect_timeout] || opts[:timeout] || 5_000,
      application_name: opts[:application_name] || "moebius",
      nulls: [nil, :null],
      codecs: @codecs
    }
    |> put_password(password)
    |> put_ssl(opts)
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp host(opts, port) do
    case opts[:socket_dir] do
      nil -> to_charlist(opts[:hostname] || "localhost")
      dir -> {:local, Path.join(dir, ".s.PGSQL.#{port}")}
    end
  end

  defp to_port(port) when is_integer(port), do: port
  defp to_port(port) when is_binary(port), do: String.to_integer(port)

  # a fun keeps the password out of crash reports
  defp put_password(map, nil), do: map
  defp put_password(map, password), do: Map.put(map, :password, fn -> password end)

  defp put_ssl(map, opts) do
    case opts[:ssl] do
      nil -> map
      false -> map
      ssl -> map |> Map.put(:ssl, ssl) |> Map.put(:ssl_opts, opts[:ssl_opts] || [])
    end
  end

  @doc false
  # Runs once on every new connection, before the pool hands it out (pooler's initialize_mfa).
  def setup(pid, settings) do
    Enum.reduce_while(settings, :ok, fn {name, value}, :ok ->
      case :epgsql.equery(pid, "select set_config($1, $2, false)", [
             to_string(name),
             to_string(value)
           ]) do
        {:ok, _, _} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, Error.from_epgsql(error)}}
      end
    end)
  end

  @doc false
  # Parses the statement, checks every parameter against the type Postgres expects, then
  # runs it. Checking first matters: epgsql encodes parameters inside the connection
  # process, and a value of the wrong type crashes that process.
  def query(pid, sql, params) do
    with {:ok, statement} <- parse(pid, sql),
         {:ok, params} <- Moebius.Params.check(statement_types(statement), params) do
      pid
      |> :epgsql.prepared_query(statement, params)
      |> to_result(pid)
    end
  catch
    :exit, reason -> {:error, lost(pid, reason)}
  end

  @doc false
  # The simple protocol: several statements in one string, no parameters, text results.
  # Used for BEGIN/COMMIT/ROLLBACK and SQL scripts.
  def script(pid, sql) do
    pid
    |> :epgsql.squery(sql)
    |> List.wrap()
    |> Enum.find_value(:ok, fn
      {:error, error} -> {:error, Error.from_epgsql(error)}
      _ok -> nil
    end)
  catch
    :exit, reason -> {:error, lost(pid, reason)}
  end

  @doc false
  # The last statement's command tag, e.g. :commit, or :rollback for a failed transaction.
  def status(pid) do
    case :epgsql.get_cmd_status(pid) do
      {:ok, {command, _count}} -> command
      {:ok, command} -> command
    end
  end

  defp parse(pid, sql) do
    case :epgsql.parse(pid, sql) do
      {:ok, statement} -> {:ok, statement}
      {:error, error} -> {:error, Error.from_epgsql(error)}
    end
  end

  # the #statement{} record: {:statement, name, columns, types, parameter_info}
  defp statement_types({:statement, _name, _columns, types, _info}), do: types

  defp to_result({:ok, columns, rows}, pid), do: {:ok, result(pid, columns, rows, length(rows))}
  defp to_result({:ok, count}, pid), do: {:ok, %Result{command: command(pid), num_rows: count}}

  defp to_result({:ok, count, columns, rows}, pid),
    do: {:ok, result(pid, columns, rows, count)}

  defp to_result({:error, error}, _pid), do: {:error, Error.from_epgsql(error)}

  # DDL and the like come back as a select of nothing; report them as no rows at all
  defp result(pid, [], _rows, _count), do: %Result{command: command(pid), num_rows: 0}

  defp result(pid, columns, rows, count) do
    %Result{
      command: command(pid),
      columns: Enum.map(columns, &column_name/1),
      rows: Enum.map(rows, &Tuple.to_list/1),
      num_rows: count
    }
  end

  # the #column{} record: {:column, name, type, oid, size, modifier, format, table_oid, table_attr}
  defp column_name(column), do: elem(column, 1)

  defp command(pid), do: status(pid)

  # The connection process died or stopped answering. Flag it, so the pool replaces it
  # instead of handing it to the next caller.
  defp lost(pid, reason) do
    Process.put({__MODULE__, :broken, pid}, true)
    %Error{name: :connection_lost, message: "connection lost: #{exit_reason(reason)}"}
  end

  defp exit_reason({{reason, stack}, {:gen_server, :call, _}}) when is_list(stack),
    do: inspect(reason)

  defp exit_reason({reason, {:gen_server, :call, _}}), do: inspect(reason)
  defp exit_reason(reason), do: inspect(reason)

  @doc false
  def broken?(pid), do: Process.delete({__MODULE__, :broken, pid}) == true
end
