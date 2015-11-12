defmodule Moebius.DocumentQuery do

  @moduledoc """
  If you like your Postgres doing document goodness, then you'll want to use this interface. Just include it in your module
  and you can work directly with JSONB in PostgreSQL. We've tried to keep reasonable parity with
  the Query interface, but there are some concepts here that are a bit different.

  This entire module is predicated on a very particular structure for your document table. You don't need to
  create this table yourself, we'll do it for you on `save/2` if it does not exist.

  If you want to create it yourself, the SQL is:

  ```sql
  create table NAME(
    id serial primary key not null,
    body jsonb not null,
    search tsvector,
    created_at timestamptz not null default now(),
    updated_at timestamptz
  );

  -- index the search and jsonb fields
  create index idx_NAME_search on NAME using GIN(search);
  create index idx_NAME on NAME using GIN(body jsonb_path_ops);
  ```

  Using this structure we can apply some convention, making this interface particularly compelling. Of primary note is the Full Text search,
  this ability (and speed) is what sets PostgreSQL above other document systems.
  """

  import Poison


  def transaction(fun), do: Moebius.Query.transaction(fun)

  @doc """
  Specifies the table or view you want to query.

  :table  -   the name of the table you want to query, such as `:users`

  Example

  ```
  result = db(:users)
    |> to_list
  ```
  """
  def db(table) when is_atom(table),
    do: db(Atom.to_string(table))

  @doc """
  Specifies the table or view you want to query and is an alias for the `db/1` function using
  a string as a table name. This is useful for specifying a table within a schema.

  "table"  -   the name of the table you want to query, such as `membership.user_docs`

  Example

  ```
  result = with("membership.user_docs")
    |> to_list
  ```
  """
  def db(table),
    do: %Moebius.DocumentCommand{table_name: table}

  @doc """
  An alias for db
  """
  def with(table),  do: db(table)

  @doc """
  This is analagous to `filter` with the Query module, however this method is highly optimized for JSONB as it uses the `@` (contains)
  operator. This flexes the GIN index created for your table (see above).

  criteria:   -     A list of elements to look for. This list must be complete, partial matches won't work.

  Example:

  ```
  db(:user_docs)
    |> contains(email: "test@test.com")
    |> first
  ```
  """
  def contains(cmd, criteria) do
    map = Enum.into(criteria, %{})
    encoded = encode!(map)

    #TODO: Do we need to parameterize this? I don't think so
    where = " where #{cmd.json_field} @> '#{encoded}'"
    %{cmd | where: where, params: []}
  end

  @doc """
  Queries a table using matching string criteria. Not a good query to run on a large table as it needs to do a full scan in order to match,
  and can't use the built-in index, however if you need to do a specialized query this is a good choice. If possible, use `contains/2`

  Example:

  ```
  return = db(:user_docs)
    |> filter("body -> 'email' = $1", res.email)
    |> first
  ```
  """
  def filter(cmd, criteria, params \\ []) when is_bitstring(criteria) do
    unless is_list(params) do
      params = [params]
    end
    where = " where #{criteria}"
    %{cmd | where: where, params: params}
  end

  @doc """
  Queries a table using matching criteria. Not a good query to run on a large table as it needs to do a full scan in order to match,
  and can't use the built-in index, however if you need to do a specialized query this is a good choice. If possible, use `contains/2`

  Example:

  ```
  return = db(:user_docs)
    |> filter(:id, ">", 100)
    |> to_list
  ```
  """
  def filter(cmd, field, operator, params) do
    unless is_list(params) do
      params = [params]
    end
    where = " where body -> '#{field}' #{operator} $1"
    %{cmd | where: where, params: params}
  end

  @doc """
  Queries a table using the existence operator. Not a good query to run on a large table as it needs to do a full scan in order to match,
  and can't use the built-in index, however if you need to query embedded arrays this is a good choice. If possible, use `contains/2`

  Example:

  ```
  return = db(:user_docs)
    |> exists(:pets, "skippy") # :pets is an array
    |> to_list
  ```
  """
  def exists(cmd, field, params) do
    unless is_list(params) do
      params = [params]
    end
    where = " where body -> '#{field}' ? $1"
    %{cmd | where: where, params: params}
  end

  @doc """
  Creates a SELECT command based on the assembled pipeline.
  """
  def select_command(cmd) do
    sql = """
    select id, #{cmd.json_field}::text
    from #{cmd.table_name}
    #{cmd.where}
    #{cmd.order}
    #{cmd.limit}
    #{cmd.offset};
    """
    %{cmd | sql: sql}
  end

  @doc """
  Alias for Query limit
  """
  def limit(cmd, length), do: Moebius.Query.limit(cmd, length)
  @doc """
  Alias for Query offset
  """
  def offset(cmd, length), do: Moebius.Query.offset(cmd, length)
  @doc """
  Alias for function
  """

  @doc """
  Sorts the query based on the supplied criteria.

  Example:

  ```
  return = db(:user_docs)
    |> exists(:pets, "skippy") # :pets is an array
    |> sort(:city)
    |> to_list
  ```
  """
  def sort(cmd, cols, direction \\ :asc) do
    order_column = cols
    if is_atom(cols) do
      order_column = Atom.to_string cols
    end
    sort_dir = Atom.to_string direction
    %{cmd | order: " order by body -> '#{order_column}' #{sort_dir}"}
  end

  @doc """
  Saves a given document to the database. If an `id` is present, a full UPDATE will be performed (partial updates are not possible
  with JSONB), otherwise an INSERT will happen.

  Example:

  ```
  product = %{sku: "TEST_1", name: "Test Product", description: "Just a test"}
  return = db(:products)
    |> save(product)
  ```
  """
  def save(cmd, doc) when is_list(doc), do: save(cmd, Enum.into(doc, %{}))
  def save(cmd, doc) when is_map(doc) do
    pid = Moebius.Runner.open_transaction
    res = save(cmd, pid, doc)
    Moebius.Runner.commit_and_close_transaction(pid)
    res
  end

  def save(cmd, pid, doc) when is_list(doc), do: save(cmd, pid, Enum.into(doc, %{}))
  def save(cmd, pid, doc) when is_map(doc) do
    cmd = %{cmd | pid: pid}
    try do

      cmd
        |> decide_command(doc)
        |> execute(cmd.pid)
        |> update_search(cmd)

    rescue
      RuntimeError -> create_document_table(cmd, doc)
        |> save(cmd.pid, Map.delete(doc, :id))

    end

  end

  defp update_search([], cmd),  do: []
  defp update_search(query_result, cmd) do

    if length(cmd.search_fields) > 0 do
      terms = Enum.map_join(cmd.search_fields, ", ' ', ", &"body -> '#{Atom.to_string(&1)}'")
      sql = "update #{cmd.table_name} set search = to_tsvector(concat(#{terms})) where id=#{query_result.id}"

      %Moebius.QueryCommand{sql: sql}
        |> Moebius.Query.execute(cmd.pid)

    end

    query_result
  end

  defp decide_command(cmd, doc) do
    cond do
      Map.has_key? doc, :id -> update_command(cmd, Map.delete(doc, :id), doc.id)
      true -> insert_command(cmd, doc)
    end
  end
  defp create_document_table(cmd, doc) do
    sql = """
    create table #{cmd.table_name}(
      id serial primary key not null,
      body jsonb not null,
      search tsvector,
      created_at timestamptz not null default now(),
      updated_at timestamptz
    );
    """

    res = %Moebius.QueryCommand{sql: sql} |> Moebius.Runner.execute(cmd.pid)
    %Moebius.QueryCommand{sql: "create index idx_#{cmd.table_name}_search on #{cmd.table_name} using GIN(search);"} |> Moebius.Runner.execute(cmd.pid)
    %Moebius.QueryCommand{sql: "create index idx_#{cmd.table_name} on #{cmd.table_name} using GIN(body jsonb_path_ops);"} |> Moebius.Runner.execute(cmd.pid)

    cmd
  end

  @doc """
  Marks a set of fields for indexing during save.

  Example:

  ```
  product = %{sku: "TEST_1", name: "Test Product", description: "Just a test"}
  return = db(:products)
    |> searchable([:name, :description])
    |> save(product)
  ```
  """
  def searchable({:error, err}), do: {:error ,err}
  def searchable(cmd, search_params) when is_list(search_params) do
    %{cmd | search_fields: search_params}
  end


  @doc """
  An alias for `delete/2`, removes a document with the specified ID.
  """
  def remove(cmd, id), do: delete(cmd, id)
  def remove(cmd, pid, id), do: delete(cmd, pid, id)

  @doc """
  Deletes a document with the given id
  """
  def delete(cmd, id), do: delete_command(cmd, id) |> execute(:single)
  def delete(cmd, pid, id), do: delete_command(cmd, id) |> execute(pid)

  @doc """
  An alias for `delete/1`, removes a document based on the filter setup.
  """
  def remove(cmd), do: delete(cmd)
  def remove(cmd, pid), do: delete(cmd, pid)

  @doc """
  Deletes a document based on the filter (if any)
  """
  def delete(cmd),  do: delete_command(cmd) |> execute
  def delete(cmd, pid),  do: delete_command(cmd) |> execute(pid)


  @doc """
  Executes a query and returns the first matching record

  Example:

  ```
  return = db(:user_docs)
    |> exists(:pets, "skippy") # :pets is an array
    |> sort(:city)
    |> first
  ```
  """
  def first(cmd) do
    res = cmd
      |> select_command
      |> execute(:single)

    cond do
      res == [] -> nil
      true -> res
    end
  end

  @doc """
  Finds a document based on ID using the Primary Key index. An optimized query for finding a single document.

  Example:

  ```
  return = db(:user_docs)
    |> find(12)
  ```
  """
  def find(cmd, id) when is_integer id do
    #no need to param this, it's an integer
    sql = "select id, body from #{cmd.table_name} where id=#{id}"
    %{cmd | sql: sql} |> execute(:single)
  end


  @doc """
  Performs a highly-tuned Full Text query on the indexed `search` column. This is set on `save/3`.

  Example:

  ```
  users = db(:user_docs)
    |> search("test.com")
  ```
  """
  def search(cmd, term) when is_bitstring(term)  do

    sql = """
    select id, body from #{cmd.table_name}
  	where search @@ to_tsquery($1)
  	order by ts_rank_cd(search,to_tsquery($1))  desc
    """

    %{cmd | sql: sql, params: [term]}
      |> execute

  end

  @doc """
  Performs a Full Text query using a full table scan. Not a good choice for larger tables. If possible,
  specify your search columns on `save/3` and use `search/2`.

  Example:

  ```
  users = db(:user_docs)
    |> search(for: "test.com", in: [:email])
  ```
  """
  def search(cmd, for: term, in: fields) do
    terms = Enum.map_join(fields, ", ' ', ", &"body -> '#{Atom.to_string(&1)}'")

    sql = """
    select id, body from #{cmd.table_name}
  	where to_tsvector(concat(#{terms})) @@ to_tsquery($1)
  	order by ts_rank_cd(to_tsvector(concat(#{terms})),to_tsquery($1))  desc
    """

    %{cmd | sql: sql, params: [term]}
      |> execute
  end

  @doc """
  Executes a query returning a list of items
  """
  def to_list(cmd),  do: all(cmd)

  def all(cmd) do
    cmd
      |> select_command
      |> execute
  end


  @doc """
  Executes a query returning a single item
  """
  def execute(cmd, :single) do
    cmd
      |> Moebius.Runner.execute
      |> parse_json_column(cmd)
      |> return_results(:single)
  end

  @doc """
  Executes a query returning a list of items.
  """
  def execute(cmd) do
    cmd
      |> Moebius.Runner.execute
      |> parse_json_column(cmd)
      |> return_results()
  end

  @doc """
  Executes a query as part of a transaction returning a list of items
  """
  def execute(cmd, pid) do
    cmd
      |> Moebius.Runner.execute(pid)
      |> parse_json_column(cmd)
      |> return_results(:single)
  end


  defp update_command(cmd, change, id) when is_map(change) and is_integer(id) do
    {:ok, encoded} = JSON.encode(change)
    sql = """
    update #{cmd.table_name}
    set #{cmd.json_field} = '#{encoded}'
    where id = #{id} returning id, #{cmd.json_field}::text;
    """
    %{cmd | sql: sql, type: :update}
  end




  defp delete_command(cmd, id) when is_integer(id) do
    sql = "delete from #{cmd.table_name} where id=#{id} returning *"
    %{cmd | sql: sql, type: :delete}
  end

  defp delete_command(cmd) do
    sql = "delete from #{cmd.table_name} #{cmd.where} returning *;"
    %{cmd | sql: sql, type: :delete}
  end

  defp insert_command(cmd, doc) when is_bitstring(doc) do
    sql = """
    insert into #{cmd.table_name}(#{cmd.json_field})
    VALUES('#{doc}')
    RETURNING id, #{cmd.json_field}::text;
    """
    %{cmd | sql: sql, params: [doc], type: :insert}
  end

  defp insert_command(cmd, doc) when is_list(doc) or is_map(doc) do
    {:ok, encoded} = JSON.encode(doc)
    insert_command(cmd, encoded)
  end


  defp return_results({:error, err}), do: {:error, err}
  defp return_results([results], :single), do: results
  defp return_results(results, :single), do: results
  defp return_results(results), do: results

  defp parse_json_column({:error, err}, cmd), do: {:error, err}
  defp parse_json_column({:ok, res}, cmd) do
    Enum.map(res.rows, &handle_row/1)
  end

  defp handle_row([id, json]) do
    decode_json(json) |> Map.put_new(:id, id)
  end

  defp decode_json(json) when is_map(json), do: json
  defp decode_json(json), do: decode!(json, keys: :atoms!)


end
