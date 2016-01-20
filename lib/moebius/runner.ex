defmodule Moebius.Runner do
  @moduledoc """
  The main execution bits are in here.
  """

  @doc """
  Spawn a Postgrex worker to run our query using the config specified in /config
  """
  def connect do
    extensions = [{Postgrex.Extensions.JSON, library: Poison}]

    Application.get_env(:moebius, :connection)
    |> Keyword.update(:extensions, extensions, &(&1 ++ extensions))
    |> Postgrex.start_link
  end

  @doc """
  If there isn't a connection process started then one is added to the command
  """
  def execute(cmd) do
    {:ok, pid} = connect()

    case Postgrex.query(pid, cmd.sql, cmd.params) do
      {:ok, result} -> {:ok, result}
      {:error, err} -> {:error, err.postgres.message}
    end

  end

  @doc """
  Executes a command for a given transaction specified with `pid`. If the execution fails,
  it will be caught in `Query.transaction/1` and reported back using `{:error, err}`.
  """
  def execute(cmd, pid) when is_pid(pid) do
    case Postgrex.query(pid, cmd.sql, cmd.params) do
      {:ok, result} ->
        {:ok, result}
      {:error, err} ->
        Postgrex.query pid, "ROLLBACK", []
        #this will get caught by the transactor
        raise err.postgres.message
    end
  end


  def open_transaction() do
    {:ok, pid} = Moebius.Runner.connect()
    Postgrex.query(pid, "BEGIN;",[])
    pid
  end

  def commit_and_close_transaction(pid) when is_pid(pid) do
    Postgrex.query(pid, "COMMIT;",[])
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
