defmodule Moebius.Query do

  import Inflex, only: [singularize: 1]
  alias Moebius.QueryCommand
  alias Moebius.CommandBatch
  use Moebius.QueryFilter

  @moduledoc """
  The main query interface for Moebius. Import this module into your code and query like a champ
  """

  @doc """
  Specifies the table or view you want to query and returns a QueryCommand struct.

  "table"  -   the name of the table you want to query, such as `membership.users`
  :table  -   the name of the table you want to query, such as `:users`

  Example

  ```
  result = db(:users)
    |> to_list

  result = db("membership.users")
    |> to_list
  ```

  Or if you prefer more SQL-like syntax, you can use _from_, which is an alias for _db_:

  ```
  result = from(:users)
    |> to_list
  ```
  """
  def db(table) when is_atom(table),
    do: db(Atom.to_string(table))

  def db(table),
    do: %QueryCommand{table_name: table}

  defdelegate from(table), to: __MODULE__, as: :db

  @doc """
  Executes a given pipeline and returns the last matching result. You should specify a `sort` to be sure first works as intended.
  cols  -   Any columns (specified as a string) that you want to have aliased or restricted in your return.
            For example `now() as current_time, name, description`. Defaults to "*"
  Example:
  ```
  cheap_skate = db(:users)
    |> sort(:money_spent, :desc)
    |> last("first, last, email")
  ```
  """
  def last(%QueryCommand{} = cmd, sort_by) when is_atom(sort_by) do
    cmd
    |> sort(sort_by, :desc)
    |> select

  end

  @doc """
  Sets the order by. Ascending using `:asc` is the default, you can send in `:desc` if you like.

  col             -  The atomized name of the column, such as `:company`
  dir (optional)  -  `:asc` (default) or `:desc`

  Example of single order by:
  ```
  result = db(:users)
      |> sort(:name, :desc)
      |> to_list
  ```

  Example of multiple order by:
  ```
  result = db(:users)
      |> sort(id: :asc, name: :desc)
      |> to_list
  ```

  Or if you prefer more SQL-like syntax, you can use "order_by", which is an alias for "sort":

  ```
  result = db(:users)
      |> order_by(id: :asc, name: :desc)
      |> to_list
  ```
  """
  def sort(%QueryCommand{} = cmd, col, dir) when is_atom(col) do
    sort(cmd, Atom.to_string(col), dir)
  end

  def sort(%QueryCommand{} = cmd, col, dir) when is_binary(col) do
    %{cmd | order: " order by #{col} #{dir}"}
  end

  def sort(%QueryCommand{} = cmd, criteria) when is_list(criteria) do
    orders =
      criteria
      |> Enum.map(fn {col, dir} -> "#{col} #{dir}" end)
      |> Enum.join(", ")

    %{cmd | order: " order by #{orders}"}
  end

  def sort(%QueryCommand{} = cmd, col), do: sort(cmd, col, :asc)

  defdelegate order_by(cmd, cols), to: __MODULE__, as: :sort
  defdelegate order_by(cmd, cols, direction), to: __MODULE__, as: :sort

  @doc """
  Sets the limit of the return.

  bound   -   And integer limiter

  Example:

  ```
  result = db(:users)
      |> limit(20)
      |> to_list
  ```
  """
  def limit(cmd, bound) when is_integer(bound),
    do: %{cmd | limit: " limit #{bound}"}

  @doc """
  Offsets the limit and is an alias for `skip/1`"

  Example:

  ```
  result = db(:users)
      |> limit(20)
      |> offset(2)
      |> to_list
  ```
  """
  def offset(cmd, n),
    do: %{cmd | offset: " offset #{n}"}

  @doc """
  Offsets the limit and is an alias for `offset/1`"

  Example:

  ```
  result = db(:users)
      |> limit(20)
      |> skip(2)
      |> to_list
  ```
  """
  def skip(%QueryCommand{} = cmd, n),
    do: offset(cmd, n)

  @doc """
  Creates a SELECT command based on the assembled pipeline. Uses the QueryCommand as its core structure.

  cols  -   Any columns (specified as a string or list) that you want to have aliased or restricted in your return.
            For example `now() as current_time, name, description`, `["name", "description"]` or `[:name, :description]`

  Example of String:
  ```
  command = db(:users)
      |> limit(20)
      |> offset(2)
      |> select("now() as current_time, name, description")

  #command is a QueryCommand object with all of the pipelined settings applied
  ```

  Example of List:
  ```
  command = db(:users)
      |> limit(20)
      |> offset(2)
      |> select([:name, :description])

  #command is a QueryCommand object with all of the pipelined settings applied
  ```
  """
  def select(%QueryCommand{} = cmd, cols \\ "*") when is_bitstring(cols) do
    select_sql(cmd, cols)
  end

  def select(%QueryCommand{} = cmd, cols) when is_list(cols) do
    select_sql(cmd, Enum.join(cols, ", "))
  end

  defp select_sql(cmd, cols) do
    %{cmd | sql: "select #{cols} from #{cmd.table_name}#{cmd.join}#{cmd.where}#{cmd.order}#{cmd.limit}#{cmd.offset};"}
  end

  @doc """
  Executes a COUNT query based on the assembled pipeline. Analogous to `map/reduce(:count)`. Returns an integer.

  Example:

  count = db(:users)
      |> limit(20)
      |> count
      |> single

  #count == 20
  """
  def count(%QueryCommand{} = cmd) do
    %{cmd | type: :count, sql: "select count(1) from #{cmd.table_name}#{cmd.join}#{cmd.where}#{cmd.order}#{cmd.limit}#{cmd.offset};"}
  end


  @doc """
  Specifies a GROUP BY for a `map/reduce` (aggregate) query.

  cols  -   An atom indicating the column to GROUP BY. Will also be part of the SELECT list.


  Example:

  ```
  result = db(:users)
    |> map("money_spent > 100")
    |> group(:company)
    |> reduce(:sum, :money_spent)
  ```

  Specifies a GROUP BY for a `map/reduce` (aggregate) query that is a string.

  cols  -   A string specifying the column to GROUP BY. Will also be part of the SELECT list.

  Example:

  ```
  result = db(:users)
    |> map("money_spent > 100")
    |> group("company, state")
    |> reduce(:sum, :money_spent)
  ```
  """
  def group(%QueryCommand{} = cmd, cols) when is_atom(cols),
    do: group(cmd, Atom.to_string(cols))

  def group(%QueryCommand{} = cmd, cols),
    do: %{cmd | group_by: cols}

  @doc """
  An alias for `filter`, specifies a range to rollup on for an aggregate query using a WHERE statement.

  criteria  -   A string, atom or list (see `filter`)

  Example:

  ```
  result = db(:users)
    |> map("money_spent > 100")
    |> reduce(:sum, :money_spent)
  ```
  """
  def map(%QueryCommand{} = cmd, criteria),
    do: filter(cmd, criteria)

  @doc """
  A rollup operation that aggregates the mapped result set by the specified operation.

  op  -   An atom indicating what you want to have happen, such as `:sum`, `:avg`, `:min`, `:max`.
          Corresponds directly to a PostgreSQL rollup function.

  Example:

  ```
  result = db(:users)
    |> map("money_spent > 100")
    |> reduce(:sum, :money_spent)
  ```
  """
  def reduce(%QueryCommand{} = cmd, op, column) when is_atom(column),
    do: reduce(cmd, op, Atom.to_string(column))

  def reduce(%QueryCommand{} = cmd, op, column) when is_bitstring(column) do
    sql = cond do
      cmd.group_by ->
        "select #{op}(#{column}), #{cmd.group_by} from #{cmd.table_name}#{cmd.join}#{cmd.where} GROUP BY #{cmd.group_by}"
      true ->
        "select #{op}(#{column}) from #{cmd.table_name}#{cmd.join}#{cmd.where}"
    end

    %{cmd | sql: sql}

  end

  @doc """
  Full text search using Postgres' built in indexing, ranked using `tsrank`. This query will result in a full table scan and is not optimized for large result
  sets. For better results, create a `tsvector` field and populate it with a trigger on insert/update. This will cause some side
  effects, one of them being that Postgrex, the Elixir driver we use, doesn't know how to resolve the tsvector type, and will throw.

  You will need to be sure that you exclude that search column from your query.

  for:  -   The string term you want to query against.
  in:   -   An atomized list of columns to search against.

  Example:

  ```
  result = db(:users)
        |> search(for: "Mike", in: [:first, :last, :email])
        |> run
  ```
  """
  def search(%QueryCommand{} = cmd, for: term, in: columns) when is_list columns do
    concat_list = Enum.map_join(columns, ", ' ',  ", &"#{&1}")
    sql = """
    select *, ts_rank_cd(to_tsvector(concat(#{concat_list})),to_tsquery($1)) as rank from #{cmd.table_name}
    where to_tsvector(concat(#{concat_list})) @@ to_tsquery($1)
    order by rank desc
    """

    %{cmd | sql: sql, params: [term]}
  end


  @doc """
  Insert multiple rows at once, within a single transaction, returning the inserted records. Pass in a composite list, containing the rows  to be inserted.
  Note, the columns to be inserted are defined based on the first record in the list. All records to be inserted must adhere to the same schema.

  Example:

  ```
  data = [
    [first_name: "John", last_name: "Lennon", address: "123 Main St.", city: "Portland", state: "OR", zip: "98204"],
    [first_name: "Paul", last_name: "McCartney", address: "456 Main St.", city: "Portland", state: "OR", zip: "98204"],
    [first_name: "George", last_name: "Harrison", address: "789 Main St.", city: "Portland", state: "OR", zip: "98204"],
    [first_name: "Paul", last_name: "Starkey", address: "012 Main St.", city: "Portland", state: "OR", zip: "98204"],

  ]
  result = db(:people) |> insert(data)
  ```
  """

  def bulk_insert(%QueryCommand{} = cmd, list) when is_list(list) do
    # do this once and get a canonnical map for the records -
    column_map = list |> hd |> Keyword.keys
    cmd
    |> bulk_insert_batch(list, [], column_map)
  end

  defp bulk_insert_batch(%QueryCommand{} = cmd, list, acc, column_map) when is_list(list) do
    # split the records into command batches that won't overwhelm postgres with params:
    # 20,000 seems to be the optimal number here. Technically you can go up to 34,464, but I think Postgrex imposes a lower limit, as I
    # hit a wall at 34,000, but succeeded at 30,000. Perf on 100k records is best at 20,000.

    max_params = 20000
    column_count = length(column_map)
    max_records_per_command = div(max_params, column_count)

    { current, next_batch } = Enum.split(list, max_records_per_command)
    new_cmd = bulk_insert_command(cmd, current, column_map)
    case next_batch do
      [] -> %CommandBatch{commands: Enum.reverse([new_cmd | acc])}
      _ -> db(cmd.table_name) |> bulk_insert_batch(next_batch, [new_cmd | acc], column_map)
    end
  end

  defp bulk_insert_command(%QueryCommand{} = cmd, list, column_map) when is_list(list) do
    column_count = length(column_map)
    row_count = length(list)

    param_list = for row <- 0..row_count-1 do
      list = (row * column_count + 1 .. (row * column_count) + column_count)
        |> Enum.to_list
        |> Enum.map_join(",", &"$#{&1}")
      "(#{list})"
    end

    params = for row <- list, {_k, v} <- row, do: v

    column_names = Enum.map_join(column_map,", ", &"#{&1}")
    value_sql = Enum.join param_list, ","
    sql = "insert into #{cmd.table_name}(#{column_names}) values #{value_sql};"
    %{cmd | sql: sql, params: params, type: :insert}
  end


  @doc """
  Creates an insert command based on the assembled pipeline
  """
  def insert(%QueryCommand{} = cmd, criteria) do
    cols = Keyword.keys(criteria)
    vals = Keyword.values(criteria)
    column_names = Enum.map_join(cols,", ", &"#{&1}")
    parameter_placeholders = Enum.map_join(1..length(cols), ", ", &"$#{&1}")
    sql = "insert into #{cmd.table_name}(#{column_names}) values(#{parameter_placeholders}) returning *;"

    %{cmd | sql: sql, params: vals, type: :insert}
  end

  @doc """
  Creates an update command based on the assembled pipeline.
  """
  def update(%QueryCommand{} = cmd, criteria) do

    cols = Keyword.keys(criteria)
    vals = Keyword.values(criteria)

    {cols, col_count} = Enum.map_reduce cols, 1, fn col, acc ->
      {"#{col} = $#{acc}", acc + 1}
    end

    #here's something for John to clean up :):)
    where = cond do

      length(cmd.where_columns) > 0 ->
        {filters, _count} = Enum.map_reduce cmd.where_columns, col_count, fn col, acc ->
          {"#{col} = $#{acc}", acc + 1}
        end
        " where " <> Enum.join(filters, " and ")

      cmd.where -> cmd.where
    end

    #add the filter criteria to the update list
    params = vals ++ cmd.params
    columns = Enum.join(cols, ", ")

    sql = "update #{cmd.table_name} set #{columns}#{where} returning *;"
    %{cmd | sql: sql, type: :update, params: params}
  end



  @doc """
  Creates a DELETE command
  """
  def delete(%QueryCommand{} = cmd) do
    sql = "delete from #{cmd.table_name}" <> cmd.where <> ";"
    %{cmd | sql: sql, type: :delete}
  end



  @doc """
  Build a table join for your query. There are a number of options to handle various joins.
  Joins can also be piped for multiple joins.

  :join        - set the type of join. LEFT, RIGHT, FULL, etc. defaults to INNER
  :on          - specify the table to join on
  :foreign_key - specify the tables foreign key column
  :primary_key - specify the joining tables primary key column
  :using       - used to specify a USING queries list of columns to join on

  Example of simple join:
  ```
    cmd = db(:customers)
        |> join(:orders)
        |> select
  ```

  Example of multiple table joins:
  ```
    cmd = db(:customers)
        |> join(:orders, on: :customers)
        |> join(:items, on: :orders)
        |> select
  ```
  """
  def join(%QueryCommand{} = cmd, table, opts \\ []) do
    join_type   = Keyword.get(opts, :join, "inner")
    join_table  = Keyword.get(opts, :on, cmd.table_name)
    foreign_key = Keyword.get(opts, :foreign_key, "#{singularize(join_table)}_id")
    primary_key = Keyword.get(opts, :primary_key, "id")
    using       = Keyword.get(opts, :using, nil)

    join_condition = case using do
      nil ->
        " #{join_type} join #{table} on #{join_table}.#{primary_key} = #{table}.#{foreign_key}"
      cols ->
        " #{join_type} join #{table} using (#{Enum.join(cols, ", ")})"
    end

    %{cmd | join: [cmd.join|join_condition]}
  end

  @doc """
  Executes the SQL in a given SQL file without parameters. Specify the scripts directory by setting the `scripts` directive in the config.
  Pass the file name as an atom, without extension.

  ```
  result = sql_file(:simple)
  """
  def sql_file(file) do
    file
    |> sql_file_command([])
  end


  @doc """
  Executes the SQL in a given SQL file with the specified parameters. Specify the scripts
  directory by setting the `scripts` directive in the config. Pass the file name as an atom,
  without extension.

  ```
  result = sql_file(:save_user, [1])
  ```
  """
  def sql_file(file, params) do
    file
    |> sql_file_command(params)
  end

  @doc """
  Creates a SQL File command
  """
  def sql_file_command(file, params \\ [])

  def sql_file_command(file, params) when not is_list(params),
    do: sql_file_command(file, [params])

  def sql_file_command(file, params) do
    #find the DB dir
    scripts_dir = Application.get_env(:moebius, :scripts)
    file_path = Path.join(scripts_dir, "#{Atom.to_string(file)}.sql")
    sql=File.read!(file_path)

    %Moebius.QueryCommand{sql: String.trim(sql), params: params}
  end

  @doc """
  Executes a function with the given name, passed as an atom.

  Example:

  ```
  result = db(:users)
    |> function(:all_users)

  ```
  """
  def function(function_name) do
    function_name
    |> function_command([])
  end


  @doc """
  Executes a function with the given name, passed as an atom.

  params:   -   An array of values to be passed to the function.

  Example:

  ```
  result = db(:users)
    |> function(:friends, ["mike","jane"])

  ```
  """
  def function(function_name, params) do
    function_name
    |> function_command(params)
  end


  @doc """
  Creates a function command
  """
  def function_command(function_name, params \\ [])

  def function_command(function_name, params) when not is_list(params),
    do: function_command(function_name, [params])

  def function_command(function_name, params) do
    arg_list = cond do
      length(params) > 0 ->  Enum.map_join(1..length(params), ", ", &"$#{&1}")
      true -> ""
    end

    sql = "select * from #{function_name}(#{arg_list});"
    %Moebius.QueryCommand{sql: sql, params: params}
  end


end
