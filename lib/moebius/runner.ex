defmodule Moebius.Runner do

  def connect do
    db = Application.get_env(:moebius, :connection)
    Postgrex.Connection.start_link(db)
  end

  def single(sql,args \\ []) do
    execute(sql,args)
      |> Moebius.Transformer.to_single
  end

  def query(sql,args \\ []) do
    execute(sql,args)
      |> Moebius.Transformer.to_list
  end

  def execute(cmd) do
    {:ok, pid} = connect()
    Postgrex.Connection.query(pid, cmd.sql, cmd.params)
  end

  def execute(sql, args) when is_bitstring(sql) do
    {:ok, pid} = connect()
    Postgrex.Connection.query(pid, sql, args)
  end

  def run_with_psql(sql, db) do
    #TODO: Read the DB from the config
    args = ["-d", db, "-c", sql, "--quiet", "--set", "ON_ERROR_STOP=1", "--no-psqlrc"]
    #hand off to PSQL because Postgrex can't run more than one command per query
    System.cmd "psql", args
  end

end
