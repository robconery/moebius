#this is the default database that is entirely optional
defmodule Moebius.Db do
  use Moebius.Database
end

defmodule Moebius do

  use Application
  def start(_type, _args) do
    Moebius.get_connection |> Moebius.Db.start_link
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

    args = ["-h", host, "-d", db, "-p", port, "-c", sql,"--quiet", "--set", "ON_ERROR_STOP=1", "--no-psqlrc"]

    args = cond do
      Enum.member?(opts, "user") -> args ++ ["-u", opts[:user]]
      true -> args
    end

    args = cond do
      Enum.member?(opts, "password") -> args ++ ["-W", opts[:password]]
      true -> args
    end

    System.cmd "psql", args
  end

  def system_envs(raw_opts) do
    Enum.map(Enum.into(raw_opts, %{}), fn {k, v} ->
      case v do
        {:system, env_var} ->
          case System.get_env(env_var) do
            nil -> raise "No environment variable or default set for #{env_var}."
            val -> {k, val}
          end
        {:system, env_var, default} ->
          case System.get_env(env_var) do
            nil -> {k, default}
            val -> {k, val}
          end
        _ -> {k, v}
      end
    end)
  end


  def get_connection(), do: get_connection(:connection)
  def get_connection(key) when is_atom(key) do
    #thanks to oskarth for this - had to pull in manually to fit to v3
    opts = system_envs(Application.get_env(:moebius, key))
    pool_opts = [pool: DBConnection.Poolboy]
    cond do
      Keyword.has_key?(opts, :url) -> Keyword.merge(opts, parse_connection(opts[:url]))
      true -> opts
    end
    opts ++ pool_opts
  end

  #thanks to the Ecto team for this code!
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

    opts = [username: username,
            password: password,
            database: database,
            hostname: info.host,
            port:     info.port]

    #strip off any nils
    Enum.reject(opts, fn {_k, v} -> is_nil(v) end)
    #send the values to a char list because that's what :epgsql likes
    # opts = for {k, v} <- opts, into: %{}, do: {k, String.to_char_list(v)}
  end

end
