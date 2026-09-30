defmodule Moebius.Db do
  @moduledoc """
  A ready-made database module that reads `config :moebius, connection: [...]`. Add it to
  your supervision tree, or define your own with `use Moebius.Database`.
  """
  use Moebius.Database
end

defmodule Moebius do
  @moduledoc """
  Helpers for connection config and SQL scripts. The query builders are in
  `Moebius.Query` and `Moebius.DocumentQuery`; running them is `Moebius.Database`.

  Moebius starts no processes of its own. Add `Moebius.Db` (or your own module that uses
  `Moebius.Database`) to your supervision tree.
  """

  @doc """
  Runs a SQL script: any number of statements separated by semicolons, without parameters.
  Opens its own connection with `opts` (the same options as a database module), so it
  works before any pool is started. Returns `:ok` or `{:error, message}`.

  The mix tasks use this to load `test/db/tables.sql` and `seeds.sql`.
  """
  def run_script(sql, opts) when is_binary(sql) do
    with_connection(opts, fn pid -> Moebius.Connection.script(pid, sql) end)
  end

  @doc false
  @deprecated "Use Moebius.run_script/2, which doesn't need psql installed"
  def run_with_psql(sql, opts), do: run_script(sql, opts)

  @doc false
  # A single connection outside any pool, closed when `fun` returns.
  def with_connection(opts, fun) do
    case :epgsql.connect(Moebius.Connection.epgsql_options(opts)) do
      {:ok, pid} ->
        try do
          case fun.(pid) do
            {:error, %Moebius.Error{message: message}} -> {:error, message}
            result -> result
          end
        after
          :epgsql.close(pid)
        end

      {:error, reason} ->
        {:error, connect_error(reason)}
    end
  end

  defp connect_error(reason), do: Moebius.Error.from_epgsql(reason).message

  def get_connection(), do: get_connection(:connection)

  @doc false
  @deprecated "Pool options go in the connection options; see Moebius.Database"
  def pool_opts, do: []

  def get_connection(key) when is_atom(key) do
    opts = Application.get_env(:moebius, key) || []

    case opts[:url] do
      nil -> opts
      url -> Keyword.merge(parse_connection(url), opts)
    end
  end

  # thanks to the Ecto team for this code!
  def parse_connection(url) when is_binary(url) do
    info = url |> URI.decode() |> URI.parse()

    if info.host in [nil, ""] do
      raise ArgumentError, "invalid database URL: host is not present"
    end

    if is_nil(info.path) or not (info.path =~ ~r"^/([^/])+$") do
      raise ArgumentError, "invalid database URL: path should be a database name"
    end

    # only the first colon separates user from password; a password may contain colons
    destructure [username, password], info.userinfo && String.split(info.userinfo, ":", parts: 2)
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
