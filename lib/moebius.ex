defmodule Moebius do
  require Logger
  use Application

  def start(_type, _args) do
    children = [

    ]
    opts = [strategy: :one_for_one, name: Moebius.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def start_pool(conn, name \\ :default, size \\ 10) do
    import Supervisor.Spec, warn: false
    Logger.debug "Starting up Moebius with :default connection pool (#{size})"
    poolboy_config = [
      {:name, {:local, name}},
      {:worker_module, Moebius.Pool.Worker},
      {:size, size},
      {:max_overflow, 5}
    ]
    children = [
      :poolboy.child_spec(name, poolboy_config, connection: conn)
    ]
    options = [
      strategy: :one_for_one,
      name: Moebius.Pool.Supervisor
    ]

    Supervisor.start_link(children, options)
  end
  def run(sql, params \\ []), do: Moebius.Runner.execute(sql, params)
end