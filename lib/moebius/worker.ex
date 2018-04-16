defmodule Moebius.Worker do
  require Logger
  use GenServer

  def start_link(_state) do
    :gen_server.start_link(__MODULE__, %{pid: nil}, [])
  end

  def init(state) do
    {:ok, state}
  end

  defmodule Connector do
    require Logger
    alias Moebius.Config

    def connect() do
      host = to_charlist Config.get(:host, 'localhost')
      username = to_charlist Config.get(:username, 'meebuss')
      password = to_charlist Config.get(:password, 'password')
      database = to_charlist Config.get(:database, 'meebuss')
      port = Config.get(:port, 5432)
      reconnect = Config.get(:reconnect, :no_reconnect)

      # DO THE EPGSQL CONNECTION BS HERE:
      {:ok, pid } = :epgsql.connect host, username, password, database: database

      Logger.debug "[Connector] new connection to postgres pid #{inspect pid}..."
      pid
    end

    def ensure_connection(pid) do
      if Process.alive?(pid) do
        Logger.debug "[Connector] re-using postgres connection, pid #{inspect pid}"
        pid
      else
        Logger.debug "[Connector] postgres connection has died, renew connection."
        connect()
      end
    end
  end

  def handle_call(%{command: command}, _from, %{pid: nil}) do
    pid = Connector.connect
    case command do
      :connect -> {:reply, pid, %{pid: pid}}
    end
  end

  def handle_call(%{command: command}, _from, %{pid: pid}) do
    pid = Connector.ensure_connection(pid)
    case command do
      :connect -> {:reply, pid, %{pid: pid}}
    end
  end

end