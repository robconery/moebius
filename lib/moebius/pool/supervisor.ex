# defmodule Moebius.Pool.Supervisor do
#   require Logger

#   @moduledoc """
#   Moebius connection pool supervisor to handle connections via pool and
#   reduce the number of opened connections via GenServer.
#   """
#   use Supervisor

#   def start_link(name: name, pool_size: pool_size, connection: conn) do
#     :supervisor.start_link(__MODULE__, opts)
#   end

#   def init(name: name, pool_size: pool_size, connection: conn) do
#     Logger.debug "Loading up the supervisor"
#     Logger.debug conn
#     # Here are my pool options
#     pool_options = [
#       name: {:local, name},
#       worker_module: Moebius.Pool.Worker,
#       size: pool_size,
#       max_overflow: 2
#     ]

#     children = [
#       :poolboy.child_spec(name, pool_options, conn)
#     ]

#     supervise(children, strategy: :one_for_one)
#   end

#   @doc """
#   Making query via connection pool using `%{command: command, params: params}` pattern.
#   """
#   def connect() do
#     pid = :poolboy.transaction(@pool_name, fn(worker) -> GenServer.call(worker, %{command: :connect}) end, Config.get(:timeout, 5000))
#     {:ok, pid}
#   end

#   # def p(args) do
#   #   :poolboy.transaction(@pool_name, fn(worker) -> GenServer.call(worker, %{command: :query_pipe, params: args}) end, Config.get(:timeout, 5000))
#   # end
# end
