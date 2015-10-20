defmodule Moebius.Query do

  @moduledoc """
  The main query interface for Moebius. Import this module into your code and query like a champ
  """

  @doc """
  The main starting point. Currently you specify a table here but, possibly, in the future you can override connection settings.
  """
  def db(table) when is_atom(table),
    do: db(Atom.to_string(table))

  def db(table),
    do: %Moebius.QueryCommand{table_name: table}

  @doc """
  A basic "WHERE" statement builder that builds a NOT IN statement

  Example:

  ```
  {:ok, res} = db(:users)
      |> filter(:name, not_in: ["mark", "biff", "skip"])
      |> select
      |> run
  ```
  """
  def filter(cmd, criteria, not_in: params) when is_atom(criteria) and is_list(params) do
    #this is an IN query
    in_list = Enum.map_join(1..length(params), ", ", &"$#{&1}")
    where = " where #{Atom.to_string(criteria)} NOT IN(#{in_list})"
    %{cmd | where: where, params: params}
  end

  @doc """
  A basic "WHERE" statement builder that builds an IN statement

  Example:

  ```
  {:ok, res} = db(:users)
      |> filter(:name, in: ["mark", "biff", "skip"])
      |> select
      |> run
  ```
  """
  def filter(cmd, criteria, in: params) when is_atom(criteria) and is_list(params),  do: filter(cmd, criteria, params)
  def filter(cmd, criteria, params) when is_atom(criteria) and is_list(params) do
    #this is an IN query
    in_list = Enum.map_join(1..length(params), ", ", &"$#{&1}")
    where = " where #{Atom.to_string(criteria)} IN(#{in_list})"
    %{cmd | where: where, params: params}
  end

  @doc """
  A basic "WHERE" statement builder that builds an IN statement

  Example:

  ```
  {:ok, res} = db(:users)
      |> filter(:name, ["mark", "biff", "skip"])
      |> select
      |> run
  ```
  """
  def filter(cmd, criteria) when is_bitstring(criteria), do: filter(cmd, criteria, [])
  def filter(cmd, criteria, params) when is_bitstring(criteria)  do
    unless is_list params do
      params = [params]
    end
    %{cmd | params: params, where: " where " <> criteria}
  end

  @doc """
  A basic "WHERE" statement builder that builds an inclusive AND-based where statement

  Example:

  ```
  {:ok, res} = db(:users)
      |> filter(name: "Mike")
      |> select
      |> run
  ```
  """
  def filter(cmd, criteria) when is_list(criteria) do

    cols = Keyword.keys(criteria)
    vals = Keyword.values(criteria)

    {filters, _count} = Enum.map_reduce cols, 1, fn col, acc ->
      {"#{col} = $#{acc}", acc + 1}
    end

    where = " where " <> Enum.join(filters, " and ")

    %{cmd | params: vals, where: where, where_columns: cols}
  end

  @doc """
  Sets the order by. Ascending using `:asc` is the default, you can send in `:desc` if you like.

  Example:

  ```
  {:ok, res} = db(:users)
      |> filter(id: 1, name: "Steve")
      |> sort(:name, :desc)
      |> select
      |> run
  ```
  """
  def sort(cmd, cols, direction \\ :asc) do
    order_column = cols
    if is_atom(cols) do
      order_column = Atom.to_string cols
    end
    sort_dir = Atom.to_string direction
    %{cmd | order: " order by #{order_column} #{sort_dir}"}
  end


  @doc """
  Sets the limit of the return.

  Example:

  ```
  {:ok, res} = db(:users)
      |> limit(20)
      |> select
      |> run
  ```
  """
  def limit(cmd, bound) do
    %{cmd | limit: " limit #{bound}"}
  end

  @doc """
  Offsets the limit - so would produce SQL like "select * from users limit 10 offset 2;"

  Example:

  ```
  {:ok, res} = db(:users)
      |> limit(20)
      |> offset(2)
      |> select
      |> run
  ```
  """
  def offset(cmd, skip) do
    %{cmd | offset: " offset #{skip}"}
  end

  @doc """
  Builds the select statement based on what was piped together

  Example:

  ```
  {:ok, res} = db(:users)
      |> limit(20)
      |> offset(2)
      |> select
      |> run
  ```
  """
  def select(cmd, cols \\ "*") do
    %{cmd | sql: "select #{cols} from #{cmd.table_name}#{cmd.where}#{cmd.order}#{cmd.limit}#{cmd.offset};"}
  end

  @doc """
  Full text search using Postgres' built in indexing.

  Example:

  ```
  {:ok, res} = db(:users)
        |> search("Mike", [:first, :last, :email])
        |> run
  ```
  """
  def search(cmd, term, columns) when is_list columns do
    concat_list = Enum.map_join(columns, ", ' ',  ", &"#{&1}")
    sql = """
    select *, ts_rank_cd(to_tsvector(concat(#{concat_list})),to_tsquery($1)) as rank from #{cmd.table_name}
  	where to_tsvector(concat(#{concat_list})) @@ to_tsquery($1)
  	order by rank desc
    """

    %{cmd | sql: sql, params: [term]}
  end

  @doc """
  A simple insert. Create your list of data and send it on in.

  Example:

  ```
  {:ok, res} = db(:users)
      |> insert(email: "test@test.com", first: "Test", last: "User")
      |> execute
  ```
  """
  def insert(cmd, criteria) do
    cols = Keyword.keys(criteria)
    vals = Keyword.values(criteria)

    sql = "insert into #{cmd.table_name}(" <> Enum.map_join(cols, ", ", &"#{&1}") <> ")" <>
    " values(" <> Enum.map_join(1..length(cols), ", ", &"$#{&1}") <> ") returning *;"

    %{cmd | sql: sql, params: vals, type: :insert}
  end


  @doc """
  A simple update based on the criteria you specify.

  Example:

  ```
  {:ok, res} = db(:users)
      |> filter(id: 1)
      |> update(email: "maggot@test.com")
      |> execute
  ```
  """
  def update(cmd, criteria) when is_list(criteria) do
    cols = Keyword.keys(criteria)
    vals = Keyword.values(criteria)

    {cols, count} = Enum.map_reduce cols, 1, fn col, acc ->
      {"#{col} = $#{acc}", acc + 1}
    end

    #here's something for John to clean up :):)
    where = cond do

      length(cmd.where_columns) > 0 ->
        {filters, _count} = Enum.map_reduce cmd.where_columns, count, fn col, acc ->
          {"#{col} = $#{acc}", acc + 1}
        end
        " where " <> Enum.join(filters, " and ")

      cmd.where -> cmd.where
    end

    params = cond do
      length(cmd.params) > 0 && length(vals) > 0 ->
        List.flatten(vals,cmd.params)
      length(vals) > 0 -> vals
    end

    sql = "update #{cmd.table_name} set " <> Enum.join(cols, ", ") <> where <> " returning *;"
    %{cmd | sql: sql, type: :update, params: params}
  end

  @doc """
  Deletes a record based on your filter.

  Example:

  ```
  db(:users)
    |> filter("id > $1", 1)
    |> delete
    |> execute
  ```
  """
  def delete(cmd) do
    sql = "delete from #{cmd.table_name}" <> cmd.where <> " returning *;"
    %{cmd | sql: sql, type: :delete}
  end


  @doc """
  Executes the SQL in a given SQL file. Specify this by setting the `scripts` directive in the config. Pass the file name as an atom, without extension.

  ```
  {:ok, res} = sql_file(:simple, 1)
    |> run
  """
  def sql_file(file, params \\ []) do

    unless is_list params do
      params = [params]
    end

    #find the DB dir
    scripts_dir = Application.get_env(:moebius, :scripts)
    file_path = Path.join(scripts_dir, "#{Atom.to_string(file)}.sql")
    sql=File.read!(file_path)

    %Moebius.QueryCommand{sql: String.strip(sql), params: params}
  end

  @doc """
  Executes a function with the given name, passed as an atom.

  Example:

  ```
  {:ok, res} = db(:users)
    |> function(:all_users, name: "steve")
    |> run

  ```
  """

  def function(cmd, function_name, params \\ []) do
    fname = function_name

    if is_atom(function_name) do
      fname = Atom.to_string(function_name)
    end

    unless is_list params do
      params = [params]
    end

    arg_list = cond do
      length(params) > 0 ->  Enum.map_join(1..length(params), ", ", &"$#{&1}")
      true -> ""
    end

    sql = "select * from #{fname}(#{arg_list});"
    %{cmd | sql: sql, params: params}
  end

  @doc """
  Executes a given pipeline and returns a single result as a map.
  """
  def single(cmd) do
     Moebius.Runner.execute(cmd.sql, cmd.params)
       |> Moebius.Transformer.to_single
  end

  @doc """
  Executes a raw SQL query without parameters
  """
  def run(sql) when is_bitstring(sql) do
    Moebius.Runner.execute(sql, [])
      |> Moebius.Transformer.to_list
  end

  @doc """
  Executes a raw SQL query with paramters
  """
  def run(sql, params) when is_bitstring(sql) do
    Moebius.Runner.execute(sql, params)
      |> Moebius.Transformer.to_list
  end

  @doc """
  Executes a given pipeline and returns a list of mapped results
  """
  def run(cmd) do
    Moebius.Runner.execute(cmd.sql, cmd.params)
      |> Moebius.Transformer.to_list
  end

  @doc """
  Executes a pass-through query and returns a single result
  """
  def execute(cmd) do
    Moebius.Runner.execute(cmd.sql, cmd.params)
      |> Moebius.Transformer.to_single
  end

  def execute(cmd, pid) do
    #this is a passed-in process from an open transaction
    Postgrex.Connection.query(pid, cmd.sql,cmd.params)
      |> Moebius.Transformer.to_single
  end


end
