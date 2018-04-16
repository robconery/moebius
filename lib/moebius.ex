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

  def run(sql, params \\ []) when is_binary(sql) do 
    Moebius.Runner.execute(sql, params)
  end
  
  def all({:select, %{sql: sql, params: params}}) do 
    res = run(sql, params) 
    |> Moebius.Transformer.to_list
    {:ok, res}
  end
  
  def table(name) do
    table_name = Atom.to_string(name)
    {:select, %{table: table_name, sql: "select * from #{table_name}", where: "", limit: 1000, order: "", params: []}}
  end
end