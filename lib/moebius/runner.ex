defmodule Moebius.Runner do
  @moduledoc """
  The main execution bits are in here.
  """
  @name __MODULE__

  @doc """
  Spawn a Postgrex worker to run our query using the config specified in /config
  """
  def start_link() do
    extensions = [{Postgrex.Extensions.JSON, library: Poison}]
    opts()
      |> Keyword.update(:extensions, extensions, &(&1 ++ extensions))
      |> Keyword.put(:name, @name)
      |> Postgrex.start_link()
  end

  defp opts do
    Application.get_env(:moebius, :connection, [])
  end

  @doc """
  If there isn't a connection process started then one is added to the command
  """
  def execute(cmd) do
    case Postgrex.query(@name, cmd.sql, cmd.params, opts()) do
      {:ok, result} -> {:ok, result}
      {:error, err} -> {:error, err.postgres.message}
    end

  end

  @doc """
  Executes a command for a given transaction specified with `pid`. If the execution fails,
  it will be caught in `Query.transaction/1` and reported back using `{:error, err}`.
  """
  def execute(cmd, %DBConnection{} = meta) do

    case Postgrex.query(meta, cmd.sql, cmd.params, opts()) do
      {:ok, result} ->
        {:ok, result}
      {:error, err} ->
        Postgrex.query meta, "ROLLBACK", []
        #this will get caught by the transactor
        raise err.postgres.message
        #{:error, err.postgres.message}
    end
  end


  @doc """
  A convenience tool for assembling large queries with multiple commands. Not used
  currently. These functions hand off to PSQL because Postgrex can't run more than
  one command per query.
  """
  def run_with_psql(sql, db \\ nil) do
    db = db || opts()[:database]
    ["-d", db, "-c", sql, "--quiet", "--set", "ON_ERROR_STOP=1", "--no-psqlrc"]
    |> call_psql
  end

  def run_file_with_psql(file, db \\ nil) do
    db = db || opts()[:database]

    ["-d", db, "-f", file, "--quiet", "--set", "ON_ERROR_STOP=1", "--no-psqlrc"]
    |> call_psql
  end

  def call_psql(args),
    do: System.cmd "psql", args
end
