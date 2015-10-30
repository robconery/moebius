defmodule Moebius.Runner do
  @moduledoc """
  The main execution bits are in here.
  """

  @doc """
  Spawn a Postgrex worker to run our query using the config specified in /config
  """
  def connect do
    db = Application.get_env(:moebius, :connection)
    
    Postgrex.Connection.start_link(db)
  end

  @doc """
    If there isn't a connection process started then one is added to the command
  """
  def execute(cmd) do
    {:ok, pid} = connect()
    try do
      case Postgrex.Connection.query(pid, cmd.sql, cmd.params) do
        {:ok, result} -> {:ok, result}
        {:error, err} -> {:error, err.postgres.message}
      end
    after
      Postgrex.Connection.stop(pid)
    end
  end

  @doc """
  Executes a command for a given transaction specified with `pid`. If the execution fails, it will be caught in `Query.transaction/1`
  and reported back using `{:error, err}`.
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
  A convenience tool for assembling large queries with multiple commands. Not used currently.
  """
  def run_with_psql(sql, db) do
    #TODO: Read the DB from the config
    args = ["-d", db, "-c", sql, "--quiet", "--set", "ON_ERROR_STOP=1", "--no-psqlrc"]
    #hand off to PSQL because Postgrex can't run more than one command per query
    System.cmd "psql", args
  end

  def run_file_with_psql(file, db) do
    #TODO: Read the DB from the config
    args = ["-d", db, "-f", file, "--quiet", "--set", "ON_ERROR_STOP=1", "--no-psqlrc"]
    IO.inspect args
    #hand off to PSQL because Postgrex can't run more than one command per query
    System.cmd "psql", args
  end
end
