defmodule Moebius.Query do
  use Moebius.QueryFilter

  alias Moebius.CommandBatch
  alias Moebius.Identifier
  alias Moebius.QueryCommand

  @moduledoc """
  The main query interface for Moebius. Import this module into your code and query like a champ
  """

  @doc """
  Specifies the table or view you want to query and returns a QueryCommand struct.

  "table"  -   the name of the table you want to query, such as `membership.users`
  :table  -   the name of the table you want to query, such as `:users`

  Example

  ```
  result =
    db(:users)
    |> to_list

  result =
    db("membership.users")
    |> to_list
  ```

  Or if you prefer more SQL-like syntax, you can use _from_, which is an alias for _db_:

  ```
  result =
    from(:users)
    |> to_list
  ```
  """
  def db(table) when is_atom(table),
    do: db(Atom.to_string(table))

  def db(table),
    do: %QueryCommand{table_name: Identifier.name!(table)}

  defdelegate from(table), to: __MODULE__, as: :db

  @doc """
  Executes a given pipeline and returns the last matching result. You should specify a `sort` to be sure first works as intended.
  cols  -   Any columns (specified as a string) that you want to have aliased or restricted in your return.
            For example `now() as current_time, name, description`. Defaults to "*"
  Example:
  ```
  cheap_skate =
    db(:users)
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
  result =
    db(:users)
    |> sort(:name, :desc)
    |> to_list
  ```

  Example of multiple order by:
  ```
  result =
    db(:users)
    |> sort(id: :asc, name: :desc)
    |> to_list
  ```

  Or if you prefer more SQL-like syntax, you can use "order_by", which is an alias for "sort":

  ```
  result =
    db(:users)
    |> order_by(id: :asc, name: :desc)
    |> to_list
  ```
  """
  def sort(%QueryCommand{} = cmd, col, dir) do
    %{cmd | order: " order by #{order_term(col, dir)}"}
  end

  def sort(%QueryCommand{} = cmd, criteria) when is_list(criteria) do
    orders = Enum.map_join(criteria, ", ", fn {col, dir} -> order_term(col, dir) end)

    %{cmd | order: " order by #{orders}"}
  end

  def sort(%QueryCommand{} = cmd, col), do: sort(cmd, col, :asc)

  # a column given as an atom is a name and is checked; a string is an expression, used as is
  defp order_term(col, dir) when is_atom(col),
    do: "#{Identifier.name!(col)} #{Identifier.direction!(dir)}"

  defp order_term(col, dir) when is_binary(col), do: "#{col} #{Identifier.direction!(dir)}"

  defp column(col) when is_atom(col), do: Identifier.name!(col)
  defp column(col) when is_binary(col), do: col

  defdelegate order_by(cmd, cols), to: __MODULE__, as: :sort
  defdelegate order_by(cmd, cols, direction), to: __MODULE__, as: :sort

  @doc """
  Sets the limit of the return.

  bound   -   And integer limiter

  Example:

  ```
  result =
    db(:users)
    |> limit(20)
    |> to_list
  ```
  """
  def limit(cmd, bound) when is_integer(bound) and bound >= 0,
    do: %{cmd | limit: " limit #{bound}"}

  @doc """
  Offsets the limit and is an alias for `skip/1`"

  Example:

  ```
  result =
    db(:users)
    |> limit(20)
    |> offset(2)
    |> to_list
  ```
  """
  def offset(cmd, n) when is_integer(n) and n >= 0,
    do: %{cmd | offset: " offset #{n}"}

  @doc """
  Offsets the limit and is an alias for `offset/1`"

  Example:

  ```
  result =
    db(:users)
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
  command =
    db(:users)
    |> limit(20)
    |> offset(2)
    |> select("now() as current_time, name, description")

  #command is a QueryCommand object with all of the pipelined settings applied
  ```

  Example of List:
  ```
  command =
    db(:users)
    |> limit(20)
    |> offset(2)
    |> select([:name, :description])

  #command is a QueryCommand object with all of the pipelined settings applied
  ```
  """
  def select(cmd, cols \\ "*")

  def select(%QueryCommand{} = cmd, cols) when is_bitstring(cols) do
    select_sql(cmd, cols)
  end

  def select(%QueryCommand{} = cmd, cols) when is_list(cols) do
    select_sql(cmd, Enum.map_join(cols, ", ", &column/1))
  end

  defp select_sql(cmd, cols) do
    %{
      cmd
      | sql:
          "select #{cols} from #{cmd.table_name}#{cmd.join}#{cmd.where}#{cmd.order}#{cmd.limit}#{cmd.offset};"
    }
  end

  @doc """
  Executes a COUNT query based on the assembled pipeline. Analogous to `map/reduce(:count)`.
  Filters and joins apply; `sort`, `limit` and `offset` are ignored, since a count is one row.

  Example:

  ```
  {:ok, %{count: count}} =
    db(:users)
    |> filter("order_count > 1")
    |> count
    |> Moebius.Db.run
  ```
  """
  # a count has one row, so sort, limit and offset don't apply (and "order by" would be invalid SQL)
  def count(%QueryCommand{} = cmd) do
    %{
      cmd
      | type: :count,
        sql: "select count(1) from #{cmd.table_name}#{cmd.join}#{cmd.where};"
    }
  end

  @doc """
  Specifies a GROUP BY for a `map/reduce` (aggregate) query.

  cols  -   An atom indicating the column to GROUP BY. Will also be part of the SELECT list.

  Example:

  ```
  result =
    db(:users)
    |> map("money_spent > 100")
    |> group(:company)
    |> reduce(:sum, :money_spent)
  ```

  Specifies a GROUP BY for a `map/reduce` (aggregate) query that is a string.

  cols  -   A string specifying the column to GROUP BY. Will also be part of the SELECT list.

  Example:

  ```
  result =
    db(:users)
    |> map("money_spent > 100")
    |> group("company, state")
    |> reduce(:sum, :money_spent)
  ```
  """
  def group(%QueryCommand{} = cmd, cols) when is_atom(cols),
    do: group(cmd, Identifier.name!(cols))

  def group(%QueryCommand{} = cmd, cols),
    do: %{cmd | group_by: cols}

  @doc """
  An alias for `filter`, specifies a range to rollup on for an aggregate query using a WHERE statement.

  criteria  -   A string, atom or list (see `filter`)

  Example:

  ```
  result =
    db(:users)
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
  result =
    db(:users)
    |> map("money_spent > 100")
    |> reduce(:sum, :money_spent)
  ```
  """
  def reduce(%QueryCommand{} = cmd, op, column) when is_atom(column),
    do: reduce(cmd, op, Identifier.name!(column))

  def reduce(%QueryCommand{} = cmd, op, column) when is_bitstring(column) do
    op = Identifier.name!(op)

    sql =
      cond do
        cmd.group_by ->
          "select #{op}(#{column}), #{cmd.group_by} from #{cmd.table_name}#{cmd.join}#{cmd.where} GROUP BY #{cmd.group_by}"

        true ->
          "select #{op}(#{column}) from #{cmd.table_name}#{cmd.join}#{cmd.where}"
      end

    %{cmd | sql: sql}
  end

  @doc """
  Full text search, ranked with `ts_rank_cd`. The `tsvector` is built on the fly, so this scans
  the table; for a large table, keep a `tsvector` column with a GIN index and query it directly.

  The term goes through `websearch_to_tsquery`, so anything a person types into a search box
  works: `"red shoes"`, `"O'Brien"`, `"apple -pie"`, `"\"exact phrase\""`.

  for:  -   The string term you want to query against.
  in:   -   An atomized list of columns to search against.

  Example:

  ```
  result =
    db(:users)
    |> search(for: "Mike", in: [:first, :last, :email])
    |> run
  ```
  """
  def search(%QueryCommand{} = cmd, for: term, in: columns) when is_list(columns) do
    concat_list = Enum.map_join(columns, ", ' ',  ", &Identifier.name!/1)

    sql = """
    select *, ts_rank_cd(to_tsvector(concat(#{concat_list})),websearch_to_tsquery($1)) as rank from #{cmd.table_name}
    where to_tsvector(concat(#{concat_list})) @@ websearch_to_tsquery($1)
    order by rank desc
    """

    %{cmd | sql: sql, params: [term]}
  end

  @doc """
  Builds multi-row inserts for a list of rows (keyword lists or maps), split into commands that
  stay under Postgres's parameter limit. Run the result with `run_batch/1`, or with
  `transact_batch/1` for all or nothing. For very large loads, `copy/3` is faster.

  The columns come from the first row; every row must have the same keys, in any order. A row
  missing a column raises `ArgumentError`. The rows are not returned.

  Example:

  ```
  data = [
    [first_name: "John", last_name: "Lennon", address: "123 Main St.", city: "Portland", state: "OR", zip: "98204"],
    [first_name: "Paul", last_name: "McCartney", address: "456 Main St.", city: "Portland", state: "OR", zip: "98204"],
    [first_name: "George", last_name: "Harrison", address: "789 Main St.", city: "Portland", state: "OR", zip: "98204"],
    [first_name: "Paul", last_name: "Starkey", address: "012 Main St.", city: "Portland", state: "OR", zip: "98204"],

  ]
  result = db(:people) |> bulk_insert(data) |> Moebius.Db.transact_batch()
  ```
  """
  def bulk_insert(%QueryCommand{} = cmd, [first | _] = list) do
    # the first row decides the columns; each row is read by those keys, not by position
    keys = row_keys(first)
    column_map = Enum.map(keys, &Identifier.name!/1)

    bulk_insert_batch(cmd, list, [], keys, column_map)
  end

  def bulk_insert(%QueryCommand{}, []),
    do: raise(ArgumentError, "bulk_insert needs at least one row")

  defp row_keys(row) when is_map(row), do: Map.keys(row)
  defp row_keys(row) when is_list(row), do: Keyword.keys(row)

  defp row_value(row, key) when is_map(row) and is_map_key(row, key), do: Map.fetch!(row, key)

  defp row_value(row, key) when is_list(row) and is_atom(key) do
    case Keyword.fetch(row, key) do
      {:ok, value} -> value
      :error -> missing_column!(key, row)
    end
  end

  defp row_value(row, key), do: missing_column!(key, row)

  defp missing_column!(key, row),
    do: raise(ArgumentError, "bulk_insert row is missing #{inspect(key)}: #{inspect(row)}")

  defp bulk_insert_batch(%QueryCommand{} = cmd, list, acc, keys, column_map) do
    # split the rows into commands that stay well under the protocol's 65,535 parameter limit;
    # 20,000 parameters per command benchmarked best on 100k rows
    max_params = 20000
    column_count = length(column_map)
    max_records_per_command = div(max_params, column_count)

    {current, next_batch} = Enum.split(list, max_records_per_command)
    new_cmd = bulk_insert_command(cmd, current, keys, column_map)

    case next_batch do
      [] -> %CommandBatch{commands: Enum.reverse([new_cmd | acc])}
      _ -> bulk_insert_batch(db(cmd.table_name), next_batch, [new_cmd | acc], keys, column_map)
    end
  end

  defp bulk_insert_command(%QueryCommand{} = cmd, list, keys, column_map) do
    column_count = length(column_map)
    row_count = length(list)

    param_list =
      for row <- 0..(row_count - 1) do
        list =
          (row * column_count + 1)..(row * column_count + column_count)
          |> Enum.to_list()
          |> Enum.map_join(",", &"$#{&1}")

        "(#{list})"
      end

    params = for row <- list, key <- keys, do: row_value(row, key)

    column_names = Enum.join(column_map, ", ")
    value_sql = Enum.join(param_list, ",")
    sql = "insert into #{cmd.table_name}(#{column_names}) values #{value_sql};"
    %{cmd | sql: sql, params: params, type: :insert}
  end

  @doc """
  Creates an insert command based on the assembled pipeline
  """
  def insert(%QueryCommand{} = cmd, [_ | _] = criteria) do
    cols = Keyword.keys(criteria)
    vals = Keyword.values(criteria)
    column_names = Identifier.names!(cols)
    parameter_placeholders = Enum.map_join(1..length(cols), ", ", &"$#{&1}")

    sql =
      "insert into #{cmd.table_name}(#{column_names}) values(#{parameter_placeholders}) returning *;"

    %{cmd | sql: sql, params: vals, type: :insert}
  end

  def insert(%QueryCommand{}, []), do: raise(ArgumentError, "insert needs at least one column")

  @doc """
  Creates an update command based on the assembled pipeline.
  """
  def update(%QueryCommand{} = cmd, [_ | _] = criteria) do
    cols = Keyword.keys(criteria)
    vals = Keyword.values(criteria)

    first_available_param = length(cmd.params) + 1

    {cols, _col_count} =
      Enum.map_reduce(cols, first_available_param, fn col, acc ->
        {"#{Identifier.name!(col)} = $#{acc}", acc + 1}
      end)

    params = cmd.params ++ vals
    columns = Enum.join(cols, ", ")

    sql = "update #{cmd.table_name} set #{columns}#{cmd.where} returning *;"
    %{cmd | sql: sql, type: :update, params: params}
  end

  def update(%QueryCommand{}, []), do: raise(ArgumentError, "update needs at least one column")

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

  Example of simple join (assumes primary key is "id" and foreign key is "customer_id"):
  ```
    cmd =
      db(:customer)
      |> join(:order)
      |> select
  ```

   Example specifying the primary key (customer.customer_id):
  ```
    cmd =
      db(:customer)
      |> join(:order, primary_key: :customer_id)
      |> select
  ```

   Example specifying the foreign key (order.customer_number):
  ```
    cmd =
      db(:customer)
      |> join(:order, foreign_key: :customer_number)
      |> select
  ```

  Example of multiple table joins:
  ```
    cmd =
      db(:customer)
      |> join(:order, on: :customer)
      |> join(:item, on: :order)
      |> select
  ```

  Example of outer joins:
  ```
    cmd =
        db(:customer)
        |> join(:order, join: :left)
        |> select
  ```
  """
  def join(%QueryCommand{} = cmd, table, opts \\ []) do
    join_type = opts |> Keyword.get(:join, :inner) |> join_type!()
    join_table = opts |> Keyword.get(:on, cmd.table_name) |> Identifier.name!()
    foreign_key = opts |> Keyword.get(:foreign_key, "#{join_table}_id") |> Identifier.name!()
    primary_key = opts |> Keyword.get(:primary_key, "id") |> Identifier.name!()
    using = opts |> Keyword.get(:using) |> using_columns()
    table = Identifier.name!(table)

    condition = join_condition(table, join_type, join_table, foreign_key, primary_key, using)

    %{cmd | join: [cmd.join | condition]}
  end

  defp join_condition(table, join_type, join_table, foreign_key, primary_key, nil) do
    " #{join_type} join #{table} on #{join_table}.#{primary_key} = #{table}.#{foreign_key}"
  end

  defp join_condition(table, join_type, _join_table, _foreign_key, _primary_key, cols) do
    " #{join_type} join #{table} using (#{cols})"
  end

  @join_types ~w(inner left right full cross)

  defp join_type!(type) do
    case type |> to_string() |> String.downcase() do
      t when t in @join_types -> t
      _ -> raise ArgumentError, "join must be one of #{Enum.join(@join_types, ", ")}"
    end
  end

  defp using_columns(nil), do: nil
  defp using_columns(cols) when is_list(cols), do: Identifier.names!(cols)

  @doc """
  Executes the SQL in a given SQL file without parameters. Specify the scripts directory by setting the `scripts` directive in the config.
  Pass the file name as an atom, without extension.

  ```
  result = sql_file(:simple)
  ```
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

  def sql_file_command(file, params) when not is_list(params) do
    sql_file_command(file, [params])
  end

  # the file name is checked by Identifier.script!/1: no "..", no absolute paths
  # sobelow_skip ["Traversal.FileModule"]
  def sql_file_command(file, params) do
    sql =
      Application.get_env(:moebius, :scripts)
      |> Path.join("#{Identifier.script!(file)}.sql")
      |> File.read!()
      |> String.trim()

    %Moebius.QueryCommand{sql: sql, params: params}
  end

  @doc """
  Executes a function with the given name, passed as an atom.

  Example:
  ```
  result =
    db(:users)
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
  result =
    db(:users)
    |> function(:friends, ["mike", "jane"])
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
    arg_list =
      cond do
        params != [] -> Enum.map_join(1..length(params), ", ", &"$#{&1}")
        true -> ""
      end

    sql = "select * from #{Identifier.name!(function_name)}(#{arg_list});"
    %Moebius.QueryCommand{sql: sql, params: params}
  end
end
