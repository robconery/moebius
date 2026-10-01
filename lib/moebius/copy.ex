defmodule Moebius.Copy do
  @moduledoc false
  # Bulk loads rows with COPY ... FROM STDIN (FORMAT binary). This is the protocol pg_dump
  # and pg_restore use: rows stream to the server in one command, with no SQL to parse
  # and no parameter limit.
  #
  # Rows are sent in chunks, so any Enumerable works, including a lazy Stream over a file
  # bigger than memory. COPY is one statement: if any row fails, none are written.
  #
  # Values are encoded by epgsql's codecs (so Decimal, DateTime, maps for jsonb all work),
  # inside the connection process. So each value is checked first with Moebius.Params,
  # exactly as query parameters are.

  alias Moebius.{Connection, Error, Identifier, Params, Pool}

  require Record

  Record.defrecordp(
    :pg_statement,
    :statement,
    Record.extract(:statement, from_lib: "epgsql/include/epgsql.hrl")
  )

  Record.defrecordp(
    :pg_column,
    :column,
    Record.extract(:column, from_lib: "epgsql/include/epgsql.hrl")
  )

  @chunk 5_000

  def copy(pool, table, rows, opts) do
    table = Identifier.name!(table)
    chunk = Keyword.get(opts, :chunk, @chunk)

    Pool.checkout(pool, fn %Connection{pid: pid} ->
      try do
        rows
        |> Stream.chunk_every(chunk)
        |> Enum.reduce_while(:not_started, &send_chunk(pid, table, opts, &1, &2))
        |> finish(pid)
      after
        # Still copying here means `rows` raised part way through. The connection is left
        # in copy mode, so it can't go back to the pool for the next caller.
        if Process.delete({__MODULE__, :copying, pid}),
          do: Process.put({Connection, :broken, pid}, true)
      end
    end)
    |> raise_in_transaction(pool)
  end

  # the first chunk decides the columns (unless :columns is given) and opens the COPY
  defp send_chunk(pid, table, opts, [first | _] = rows, :not_started) do
    columns = Keyword.get_lazy(opts, :columns, fn -> keys(first) end)
    names = Identifier.names!(columns)

    with {:ok, types} <- column_types(pid, table, names),
         :ok <- start(pid, table, names, types) do
      send_chunk(pid, table, opts, rows, {:copying, columns, types, 0})
    else
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp send_chunk(pid, _table, _opts, rows, {:copying, columns, types, sent}) do
    with {:ok, values} <- values(rows, columns, types, sent),
         :ok <- send_rows(pid, values) do
      {:cont, {:copying, columns, types, sent + length(rows)}}
    else
      {:error, error} -> {:halt, {:aborted, error}}
    end
  end

  # As in Moebius.Connection, a connection that dies under a call is an error for the caller,
  # not an exit.
  defp send_rows(pid, values) do
    case :epgsql.copy_send_rows(pid, values, :infinity) do
      :ok -> :ok
      {:error, reason} -> {:error, Error.from_epgsql(reason)}
    end
  catch
    :exit, reason -> {:error, Connection.lost(pid, reason)}
  end

  defp finish(:not_started, _pid), do: {:ok, 0}
  defp finish({:error, error}, _pid), do: {:error, error}

  defp finish({:copying, _columns, _types, _sent}, pid) do
    case server_error(pid) do
      nil -> done(pid)
      error -> abort(pid, error)
    end
  end

  defp finish({:aborted, error}, pid), do: abort(pid, server_error(pid) || error)

  defp done(pid) do
    Process.delete({__MODULE__, :copying, pid})

    case :epgsql.copy_done(pid) do
      {:ok, count} -> {:ok, count}
      {:error, error} -> {:error, Error.from_epgsql(error)}
    end
  catch
    :exit, reason -> {:error, Connection.lost(pid, reason)}
  end

  # A COPY that stopped part way leaves the connection in copy mode. Don't reuse it.
  defp abort(pid, error) do
    Process.put({Connection, :broken, pid}, true)
    {:error, error}
  end

  # epgsql reports a row the server rejected as a message to the process that opened the COPY
  defp server_error(pid) do
    receive do
      {:epgsql, ^pid, {:error, error}} -> Error.from_epgsql(error)
    after
      0 -> nil
    end
  end

  defp start(pid, table, names, types) do
    sql = "copy #{table} (#{names}) from stdin with (format binary)"

    case :epgsql.copy_from_stdin(pid, sql, {:binary, types}) do
      {:ok, _formats} ->
        Process.put({__MODULE__, :copying, pid}, true)
        :ok

      {:error, error} ->
        {:error, Error.from_epgsql(error)}
    end
  catch
    :exit, reason -> {:error, Connection.lost(pid, reason)}
  end

  # the column types, from Postgres itself: parse a select of those columns and read them back
  defp column_types(pid, table, names) do
    case :epgsql.parse(pid, "select #{names} from #{table}") do
      {:ok, pg_statement(columns: columns)} ->
        {:ok, Enum.map(columns, fn pg_column(type: type) -> type end)}

      {:error, error} ->
        {:error, Error.from_epgsql(error)}
    end
  catch
    :exit, reason -> {:error, Connection.lost(pid, reason)}
  end

  defp keys(row) when is_map(row), do: Map.keys(row)
  defp keys(row) when is_list(row), do: Keyword.keys(row)

  defp values(rows, columns, types, sent) do
    rows
    |> Enum.with_index(sent + 1)
    |> Enum.reduce_while({:ok, []}, fn {row, n}, {:ok, acc} ->
      case Params.check(types, Enum.map(columns, &field(row, &1))) do
        {:ok, values} -> {:cont, {:ok, [values | acc]}}
        {:error, error} -> {:halt, {:error, %{error | message: row_message(n, columns, error)}}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  # "parameter $2 must be int4" reads better here as "row 7, age must be int4"
  defp row_message(n, columns, %Error{message: message}) do
    message =
      Regex.replace(~r/parameter \$(\d+)/, message, fn _, i ->
        to_string(Enum.at(columns, String.to_integer(i) - 1))
      end)

    "row #{n}, #{message}"
  end

  defp field(row, column) when is_map(row), do: Map.get(row, column)
  defp field(row, column) when is_list(row), do: Keyword.get(row, column)

  # inside a transaction a failure aborts it, as with every other statement
  defp raise_in_transaction({:error, %Error{} = error}, pool) do
    if Pool.in_transaction?(pool), do: raise(error), else: {:error, error.message}
  end

  defp raise_in_transaction(result, _pool), do: result
end
