defmodule Moebius do

  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      supervisor(Moebius.Supervisor, [])
    ]

    opts = [strategy: :one_for_one, name: Moebius.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def connect() do
    res = Moebius.Supervisor.connect()
    res
  end

  def query(sql) do
    {:ok, pid} = connect()
    # just use equery for everything I think...we could check for params, but squery uses the simple query protocol, 
    # which is limited usefulness, and queries with no params work fine with the extended protocol.
    {:ok, cols, rows} = :epgsql.equery(pid, sql)
    {:ok, rows}
  end

end