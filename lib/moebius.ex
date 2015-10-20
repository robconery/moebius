defmodule Moebius do
  use Application

  def start,  do: start(:normal, [])
  def start(_type, _args) do
    Moebius.Supervisor.start_link(_type, _args)
  end

  def transaction(fun) do
    {:ok, pid} = Moebius.Runner.connect()
    Postgrex.Connection.query(pid, "BEGIN;",[])
    fun.(pid)
    Postgrex.Connection.query(pid, "COMMIT;",[])
  end


end
