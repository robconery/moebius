# this is the default database that is entirely optional
defmodule Moebius.Db do
  use Moebius.Database
end

defmodule Moebius do
  use Application

  def start(_type, _args) do
    Moebius.get_connection() |> Moebius.Db.start_link()
  end

  @doc """
  A convenience tool for assembling large queries with multiple commands which we use for testing.
  These functions hand off to PSQL because Postgrex can't run more than
  one command per query.
  """
  def run_with_psql(sql, opts) do
    port = if is_binary(opts[:port]), do: opts[:port], else: to_string(opts[:port])

    args =
      [
        "-h",
        opts[:hostname],
        "-d",
        opts[:database],
        "-p",
        port,
        "-c",
        sql,
        "--quiet",
        "--set",
        "ON_ERROR_STOP=1",
        "--no-psqlrc"
      ]

    env = set_env(opts)

    System.cmd("psql", args, env: env)
  end

  def set_env(opts) do
    cond do
      Keyword.has_key?(opts, :username) and Keyword.has_key?(opts, :password) ->
        [{"PGUSER", opts[:username]}, {"PGPASSWORD", opts[:password]}]

      Keyword.has_key?(opts, :username) ->
        [{"PGUSER", opts[:username]}]

      Keyword.has_key?(opts, :password) ->
        [{"PGPASSWORD", opts[:password]}]

      true ->
        []
    end
  end

  def get_connection(), do: get_connection(:connection)

  def pool_opts do
    [pool: DBConnection.ConnectionPool]
  end

  def get_connection(key) when is_atom(key) do
    opts = Application.get_env(:moebius, key)

    opts =
      cond do
        Keyword.has_key?(opts, :url) -> Keyword.merge(opts, parse_connection(opts[:url]))
        true -> opts
      end

    opts ++ pool_opts()
  end

  # thanks to the Ecto team for this code!
  def parse_connection(url) when is_binary(url) do
    info = url |> URI.decode() |> URI.parse()

    if is_nil(info.host) do
      raise "Invalid URL: host is not present"
    end

    if is_nil(info.path) or not (info.path =~ ~r"^/([^/])+$") do
      raise "Invalid URL: path should be a database name"
    end

    destructure [username, password], info.userinfo && String.split(info.userinfo, ":")
    "/" <> database = info.path

    opts = [
      username: username,
      password: password,
      database: database,
      hostname: info.host,
      port: info.port
    ]

    # strip off any nils
    Enum.reject(opts, fn {_k, v} -> is_nil(v) end)
    # send the values to a char list because that's what :epgsql likes
    # opts = for {k, v} <- opts, into: %{}, do: {k, String.to_char_list(v)}
  end
end
