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

end