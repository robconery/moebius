defmodule Moebius do
  use Application

  def start,  do: start(:normal, [])
  def start(type, args) do
    Moebius.Supervisor.start_link(type, args)
  end

  def transaction(fun) do
    {:ok, pid} = Moebius.Runner.connect()
    Postgrex.Connection.query(pid, "BEGIN;",[])
    res = fun.(pid)
    Postgrex.Connection.query(pid, "COMMIT;",[])
    res
  end


end
