defmodule Moebius.Runner do

  def connect do
    db = Application.get_env(:moebius, :connection)
    Postgrex.Connection.start_link(db)
  end

  def single(sql, args \\ []) do
    %Moebius.DocumentCommand{sql: sql, params: args}
      |> execute
      |> Moebius.Transformer.to_single
  end

  def query(sql, args \\ []) do
    %Moebius.DocumentCommand{sql: sql, params: args}
      |> execute
      |> Moebius.Transformer.to_list
  end

  @doc """
    If there isn't a connection process started then one is added to the command
  """
  def execute(%{pid: nil} = cmd) do
    {:ok, pid} = connect()
    Map.merge(cmd, %{pid: pid})
      |> execute
  end

  def execute(cmd) do

    #TODO: A commit will succeed no matter what - we have no way of knowing right
    #now if a tx fails.
    case Postgrex.Connection.query(cmd.pid, cmd.sql, cmd.params) do
      {:ok, result} -> {:ok, result}
      {:error, err} -> raise err.postgres.message
    end
  end

  def run_with_psql(sql, db) do
    #TODO: Read the DB from the config
    args = ["-d", db, "-c", sql, "--quiet", "--set", "ON_ERROR_STOP=1", "--no-psqlrc"]
    #hand off to PSQL because Postgrex can't run more than one command per query
    System.cmd "psql", args
  end

end
