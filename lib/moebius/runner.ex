defmodule Moebius.Runner do
  @moduledoc """
  The main execution bits are in here.
  """

  @doc """
  Spawn a Postgrex worker to run our query using the config specified in /config
  """
  def connect do
    #extensions = [{Postgrex.Extensions.JSON, library: Poison}]

    # Application.get_env(:moebius, :connection)
    #   |> Keyword.update(:extensions, extensions, &(&1 ++ extensions))
    #   |> Postgrex.Connection.start_link
    opts = Application.get_env(:moebius, :connection)
      |> parse_connection_args

    #TODO: Feeling a bit fugly about this but it works .. and :epgsql is a bit finicky about connections
    case opts do
      %{hostname: host, username: user, password: pass, database: database} -> :epgsql.connect opts.hostname, user, pass, database: opts.database
      %{hostname: host, username: user, database: database} -> :epgsql.connect opts.hostname, user, database: opts.database
      %{hostname: host, database: database} -> :epgsql.connect opts.hostname, database: opts.database
      %{database: database} -> :epgsql.connect 'localhost', database: opts.database
    end
  end

  def parse_connection_args, do: raise "Please specify a connection in your config"
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

    opts = [username: String.to_char_list(username),
            password: String.to_char_list(password),
            database: String.to_char_list(database),
            hostname: String.to_char_list(info.host),
            port:     String.to_char_list(info.port)]

    Enum.reject(opts, fn {_k, v} -> is_nil(v) end) |> Enum.into(%{})
  end

  @doc """
  If there isn't a connection process started then one is added to the command
  """
  def execute(cmd) do
    {:ok, pid} = connect
    try do
      case :epgsql.equery pid, cmd.sql, cmd.params do
        {:ok, num} -> {:ok, num}
        {:ok, num, cols, rows} -> {:ok, cols, rows}
        {:error, err} -> {:error, err.postgres.message}
      end
    after
      :epgsql.close pid
    end
  end

  @doc """
  Executes a command for a given transaction specified with `pid`. If the execution fails,
  it will be caught in `Query.transaction/1` and reported back using `{:error, err}`.
  """
  def execute(cmd, pid) do
    case Postgrex.Connection.query(pid, cmd.sql, cmd.params) do
      {:ok, result} ->
        {:ok, result}
      {:error, err} ->
        Postgrex.Connection.query pid, "ROLLBACK", []
        #this will get caught by the transactor
        raise err.postgres.message
    end
  end


  def open_transaction() do
    {:ok, pid} = Moebius.Runner.connect()
    Postgrex.Connection.query(pid, "BEGIN;",[])
    pid
  end

  def commit_and_close_transaction(pid) do
    Postgrex.Connection.query(pid, "COMMIT;",[])
    Postgrex.Connection.stop(pid)
  end

  @doc """
  A convenience tool for assembling large queries with multiple commands. Not used
  currently. These functions hand off to PSQL because Postgrex can't run more than
  one command per query.
  """
  def run_with_psql(sql, db \\ nil) do
    if db == nil,  do: [database: db] = Application.get_env(:moebius, :connection)
    ["-d", db, "-c", sql, "--quiet", "--set", "ON_ERROR_STOP=1", "--no-psqlrc"]
    |> call_psql
  end

  def run_file_with_psql(file, db \\ nil) do
    if db == nil,  do: [database: db] = Application.get_env(:moebius, :connection)

    ["-d", db, "-f", file, "--quiet", "--set", "ON_ERROR_STOP=1", "--no-psqlrc"]
    |> call_psql
  end

  def call_psql(args),
    do: System.cmd "psql", args
end
