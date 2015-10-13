defmodule Moebius.Runner do

  def connect do
    db = Application.get_env(:moebius, :connection)
    Postgrex.Connection.start_link(db)
  end

  def single(sql,args \\ []) do
    execute(sql,args)
      |> DB.Result.map_single
  end

  def query(sql,args \\ []) do
    execute(sql,args)
      |> DB.Result.map_list
  end

  def execute_single_function(function_name, args) do
    {:ok, pid} = connect()
    sql = "select * from #{function_name};"
    Postgrex.Connection.query(pid, sql, args)
      |> DB.Result.map_single
  end

  def execute(sql, args \\ []) do
    {:ok, pid} = connect()
    Postgrex.Connection.query(pid, sql, args)
  end

  def prepare_sql_batch(files) do
    #make sure its wrapped in a transaction, and stop with the annoying NOTICEs
    #NOTE: this can be run with -1 with PSQL however I want to be sure
    #that if it's put to file later, it will be clear that it's a tx
    IO.puts "Executing #{length files} statements"
    files = List.insert_at(files,0,"BEGIN;SET client_min_messages=WARNING;");
    files ++ ["COMMIT;"]
    Enum.join(files, "\r\n")
  end

  def write_batch_to_file(sql_blob) do
    build_file = Path.join("build", "db.sql")
    {:ok, file} = File.open build_file, [:write]
    IO.binwrite file, sql_blob
    File.close file
    build_file
  end

  def run_with_psql(sql, db) do
    #TODO: Read the DB from the config
    args = ["-d", db, "-c", sql, "--quiet", "--set", "ON_ERROR_STOP=1", "--no-psqlrc"]
    #hand off to PSQL because Postgrex can't run more than one command per query
    System.cmd "psql", args
  end

  def execute_sql_files_in_directory(db, sql_dir) do
    DB.Builder.read_and_concat_files(sql_dir)
      |> prepare_sql_batch
      |> run_with_psql(db)
  end

  def execute_transaction(list) do
    {:ok, pid} = connect()
    Postgrex.Connection.query(pid, "BEGIN;",[])
    execute_transaction pid, list
  end

  def execute_transaction(pid, []) do
    Postgrex.Connection.query(pid, "COMMIT;",[])
  end

  def execute_transaction(pid, [next | list]) do
    case Postgrex.Connection.query(pid, next.sql,[]) do
      {:error, err} -> raise err
      {:ok, _} ->  execute_transaction(pid, list);
    end
  end

end
