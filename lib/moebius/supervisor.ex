defmodule Moebius.Supervisor do
  use Supervisor

  def start_link(_type, _args) do
    :supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    children = [
      worker(Moebius.Runner, [])
      # Define workers and child supervisors to be supervised
    ]

    # See http://elixir-lang.org/docs/stable/Supervisor.Behaviour.html
    # for other strategies and supported options
    supervise(children, strategy: :one_for_one)
  end
end
