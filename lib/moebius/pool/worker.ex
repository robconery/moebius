defmodule Moebius.Pool.Worker do
  require Logger
  use GenServer

  #TODO: Need a better match on opts
  def start_link(connection: conn) do
    pid = Moebius.Pool.Connection.get(conn)
    :gen_server.start_link(__MODULE__, %{pid: pid}, [])
  end

  def init(state) do
    {:ok, state}
  end

  def handle_call(%{sql: sql,params: params} = command, _from, %{pid: pid} = state) do
    res = Moebius.Runner.execute(pid, sql, params)
    {:reply, res, state}
  end

  def execute(command, pid) do
    GenServer.call pid, command
  end
end