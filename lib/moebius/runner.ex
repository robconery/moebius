defmodule Moebius.Runner do
  @moduledoc """
  The main execution bits are in here.
  """

  @doc """
  Spawn a Postgrex pool to run our queries using the config specified in /config
  """
  def start_link() do
     extensions = [{Postgrex.Extensions.JSON, library: Poison}]
     opts = Keyword.update(opts(), :extensions, extensions, &(&1 ++ extensions))
     Postgrex.Connection.start_link([name: __MODULE__] ++ opts)
  end

  defp opts() do
    Application.get_env(:moebius, :connection)
    |> Keyword.put_new(:pool_mod, DBConnection.Poolboy)
    |> Keyword.put_new(:pool_size, 10)
    |> Keyword.put_new(:pool_overflow, 0)
  end

  @doc """
  If there isn't a connection process started then one is added to the command
  """
  def execute(cmd) do
    case Postgrex.Connection.query(__MODULE__, cmd.sql, cmd.params, opts()) do
      {:ok, result} -> {:ok, result}
      {:error, err} -> {:error, err.postgres.message}
    end
  end

  @doc """
  Executes a command for a given transaction specified with `pid`. If the execution fails,
  it will be caught in `Query.transaction/1` and reported back using `{:error, err}`.
  """
  def execute(cmd, pid) do
    case Postgrex.Connection.query(pid, cmd.sql, cmd.params) do
      {:ok, result} ->
        {:ok, result}
      {:error, err} ->
        Postgrex.Connection.query pid, "ROLLBACK", []
        #this will get caught by the transactor
        raise err.postgres.message
    end
  end

  @doc """
  Opens a transaction, runs a function, commits the transaction and returns the
  result.
  """
  def transaction(fun) do
    run = fn(conn) ->
      Postgrex.Connection.query(conn, "BEGIN;",[])
      res = fun.(conn)
      Postgrex.Connection.query(conn, "COMMIT;",[])
      res
    end
    DBConnection.run(__MODULE__, run, opts())
  end

  @doc """
  A convenience tool for assembling large queries with multiple commands. Not used
  currently. These functions hand off to PSQL because Postgrex can't run more than
  one command per query.
  """
  def run_with_psql(sql, db \\ nil) do
    if db == nil,  do: [database: db] = Application.get_env(:moebius, :connection)
    ["-d", db, "-c", sql, "--quiet", "--set", "ON_ERROR_STOP=1", "--no-psqlrc"]
    |> call_psql
  end

  def run_file_with_psql(file, db \\ nil) do
    if db == nil,  do: [database: db] = Application.get_env(:moebius, :connection)

    ["-d", db, "-f", file, "--quiet", "--set", "ON_ERROR_STOP=1", "--no-psqlrc"]
    |> call_psql
  end

  def call_psql(args),
    do: System.cmd "psql", args
end
