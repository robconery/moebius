defmodule Moebius.Runner do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, open_connection, name: Moby)
  end

  @moduledoc """
  The main execution bits are in here.
  """

  defp open_connection do
    extensions = [{Postgrex.Extensions.JSON, library: Poison}]

    {:ok, pid} = Application.get_env(:moebius, :connection)
              |> Keyword.update(:extensions, extensions, &(&1 ++ extensions))
              |> Postgrex.Connection.start_link

    %{pid: pid}
  end

  @doc """
  If there isn't a connection process started then one is added to the command
  """
  def execute(cmd),
    do: GenServer.call(Moby, {:execute, cmd})

  def connect,
    do: GenServer.call(Moby, {:connect})

  def handle_call({:execute, cmd}, _from, state) do
    case query(cmd, state) do
      {:ok, results} ->
        {:reply, {:ok, results}, state}
      {:error, err} ->
        {:reply, {:error, err}, state}
    end
  end

  def handle_call({:connect}, _from, %{pid: pid} = state),
    do: {:reply, {:ok, pid}, state}

  def terminate(_reason, %{pid: pid}),
    do: Postgrex.Connection.stop pid

  defp query(cmd, %{pid: pid}),
    do: Postgrex.Connection.query(pid, cmd.sql, cmd.params)

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

  def open_transaction() do
    {:ok, pid} = Moebius.Runner.connect

    Postgrex.Connection.query(pid, "BEGIN;",[])
    pid
  end

  def commit_and_close_transaction(pid) do
    Postgrex.Connection.query(pid, "COMMIT;",[])
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
