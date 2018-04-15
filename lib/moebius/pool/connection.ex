defmodule Moebius.Pool.Connection do
  require Logger
  alias Moebius.Config

  def get(opts) do
    opts = parse_connection_args(opts)
    res = case opts do
      %{hostname: host, username: user, password: pass, database: database} -> :epgsql.connect opts.hostname, user, pass, database: opts.database
      %{hostname: host, username: user, database: database} -> :epgsql.connect opts.hostname, user, database: opts.database
      %{hostname: host, database: database} -> :epgsql.connect opts.hostname, database: opts.database
      %{database: database} -> :epgsql.connect 'localhost', database: opts.database
    end
    case res do
      {:ok, pid} -> pid
      _ -> raise "There was an error connecting"
    end
  end

  def parse_connection_args, do: raise "Please specify a connection in your config"
  def parse_connection_args(args) when is_map(args) do
    args
    |> Map.to_list
    |> parse_connection_args
  end
  def parse_connection_args(args) when is_list(args) do
    for {k, v} <- args, into: %{}, do: {k, String.to_char_list(v)}
  end
  def parse_connection_args(""), do: []
  def parse_connection_args(url) when is_binary(url) do
    info = url |> URI.decode() |> URI.parse()

    if is_nil(info.host) do
      raise "Invalid URL: host is not present"
    end

    if is_nil(info.path) or not (info.path =~ ~r"^/([^/])+$") do
      raise "Invalid URL: path should be a database name"
    end

    destructure [username, password], info.userinfo && String.split(info.userinfo, ":")
    "/" <> database = info.path
    #epgsql.connect opts.hostname, user, pass, database: opts.database
    opts = [username: username,
            password: password,
            database: database,
            hostname: info.host,
            port: info.port]

    #strip off any nils
    opts = Enum.reject(opts, fn {_k, v} -> is_nil(v) end)
    #send the values to a char list because that's what :epgsql likes
    opts = for {k, v} <- opts, into: %{}, do: {k, String.to_char_list(v)}
  end
end