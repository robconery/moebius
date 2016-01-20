defmodule Moebius.Supervisor do
  use Supervisor

  def start_link(_type, _args) do
    :supervisor.start_link(__MODULE__, [])
  end

  def init([]) do
    args = Application.get_env(:moebius, :connection) |> parse_connection_args
    IO.inspect args
    Postgrex.start_link args
    # case parse_connection_args(args) do
    #   %{hostname: hostname, username: user, password: pass, database: database} -> :epgsql.connect hostname, user, pass, database: database
    #   %{hostname: hostname, username: user, database: database} -> :epgsql.connect hostname, user, database: database
    #   %{hostname: hostname, database: database} -> :epgsql.connect hostname, database: database
    #   %{database: database} -> :epgsql.connect 'localhost', database: database
    # end


    children = [
      # Define workers and child supervisors to be supervised
    ]

    # See http://elixir-lang.org/docs/stable/Supervisor.Behaviour.html
    # for other strategies and supported options
    supervise(children, strategy: :one_for_one)
  end

  defp parse_connection_args, do: raise "Please specify a connection in your config"
  defp parse_connection_args(args) when is_list(args), do: args

  defp parse_connection_args(""), do: []
  defp parse_connection_args(url) when is_binary(url) do
    info = url |> URI.decode() |> URI.parse()

    if is_nil(info.host) do
      raise "Invalid URL: host is not present"
    end

    if is_nil(info.path) or not (info.path =~ ~r"^/([^/])+$") do
      raise "Invalid URL: path should be a database name"
    end

    destructure [username, password], info.userinfo && String.split(info.userinfo, ":")
    "/" <> database = info.path

    opts = [username: username,
            password: password,
            database: database,
            hostname: info.host,
            port:     info.port]

    #strip off any nils
    Enum.reject(opts, fn {_k, v} -> is_nil(v) end)
  end

end
