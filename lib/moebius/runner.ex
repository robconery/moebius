defmodule Connection do
  defstruct pid: nil, locked: false
end

defmodule Moebius.Runner do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, fill_pool, name: Moby)
  end

  @moduledoc """
  The main execution bits are in here.
  """

  @doc """
  Spawn a Postgrex worker to run our query using the config specified in /config
  """
  defp fill_pool do
    extensions = [{Postgrex.Extensions.JSON, library: Poison}]

    Enum.map(1..5, fn(_n) ->
      {:ok, pid} = Application.get_env(:moebius, :connection)
                |> Keyword.update(:extensions, extensions, &(&1 ++ extensions))
                |> Postgrex.Connection.start_link

      %Connection{pid: pid}
    end)
  end

  @doc """
  If there isn't a connection process started then one is added to the command
  """
  def execute(cmd) do
    GenServer.call(Moby, {:execute, cmd})
  end

  def connect do
    GenServer.call(Moby, {:connect})
  end

  def handle_call({:execute, cmd}, _from, state) do
    {pid, results} = query(cmd, state)
    unlock(pid, state)
    send(self, {:unlocked, pid})
    {:reply, {:ok, results}, state}
  end

  def handle_call({:connect}, _from, state) do
    {:reply, {:ok, available_connection(state)}, state}
  end

  defp unlock(_open_id, []), do: []

  defp unlock(open_pid, [%{pid: pid, locked: true}|pool]) when open_pid == pid do
    [%{pid: open_pid, locked: false}|pool]
  end

  defp unlock(open_pid, [_pid|pool]),
    do: unlock(open_pid, pool)

  defp available_connection([]) do
    receive do
      {:unlocked, pid} ->
        pid
    after
      100 -> raise "No available connections"
    end
  end

  defp available_connection([%{pid: _pid, locked: true}|pool]),
    do: available_connection(pool)

  defp available_connection([%{pid: pid, locked: false}|_pool]),
    do: pid

  defp query(cmd, []) do
    receive do
      {:unlocked, pid} ->
        query(cmd, [%{pid: pid, locked: false}])
    after
      100 -> raise "Error querying database"
    end
  end

  defp query(cmd, [%{pid: _pid, locked: true}|pool]),
    do: query(cmd, pool)

  defp query(cmd, [%{pid: pid, locked: false}|_pool]) do
    case Postgrex.Connection.query(pid, cmd.sql, cmd.params) do
      {:ok, result} -> {pid, result}
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
  def run_with_psql(sql, db \\ @opts[:database]) do
    ["-d", db, "-c", sql, "--quiet", "--set", "ON_ERROR_STOP=1", "--no-psqlrc"]
    |> call_psql
  end

  def run_file_with_psql(file, db \\ @opts[:database]) do
    ["-d", db, "-f", file, "--quiet", "--set", "ON_ERROR_STOP=1", "--no-psqlrc"]
    |> call_psql
  end

  def call_psql(args),
    do: System.cmd "psql", args
end
