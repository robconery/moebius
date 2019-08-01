# this is the default database that is entirely optional
defmodule Moebius.Db do
  use Moebius.Database
end

defmodule Moebius do
  use Application

  def start(_type, _args) do
    Moebius.get_connection()
    |> Moebius.Db.start_link()
  end

  @doc """
  A convenience tool for assembling large queries with multiple commands which we use for testing.
  These functions hand off to PSQL because Postgrex can't run more than
  one command per query.
  """
  def run_with_psql(sql, opts) do
    db = opts[:database] || opts[:db]
    host = opts[:host] || "localhost"
    port = opts[:port] || "5432"

    args = [
      "-h",
      host,
      "-d",
      db,
      "-p",
      port,
      "-c",
      sql,
      "--quiet",
      "--set",
      "ON_ERROR_STOP=1",
      "--no-psqlrc"
    ]

    args =
      cond do
        Enum.member?(opts, "user") -> args ++ ["-u", opts[:user]]
        true -> args
      end

    args =
      cond do
        Enum.member?(opts, "password") -> args ++ ["-W", opts[:password]]
        true -> args
      end

    System.cmd("psql", args)
  end

  def get_connection(), do: get_connection(:connection)

  def pool_opts do
    # [pool: DBConnection.Poolboy]
    []
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
  end
end
