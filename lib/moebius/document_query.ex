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

  alias Moebius.DocumentCommand

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
  This is analogous to `filter` with the Query module, however this method is highly optimized for JSONB as it uses the `@` (contains)
  operator. This flexes the GIN index created for your table (see above).

  criteria:   -     A list of elements to look for. This list must be complete, partial matches won't work.

  Example:

  ```
  db(:user_docs)
    |> contains(email: "test@test.com")
    |> first
  ```
  """
  def contains(%DocumentCommand{} = cmd, criteria) do
    map = Enum.into(criteria, %{})
    encoded = Jason.encode!(map)

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
  def filter(%DocumentCommand{} = cmd, criteria, params \\ []) when is_bitstring(criteria) do

    param_list = cond do
      is_list(params) -> params
      true -> [params]
    end

    where = " where #{criteria}"
    %{cmd | where: where, params: param_list}
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
  def filter(%DocumentCommand{} = cmd, field, operator, params) do
    param_list = cond do
      is_list(params) -> params
      true -> [params]
    end
    where = " where body -> '#{field}' #{operator} $1"
    %{cmd | where: where, params: param_list}
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
  def exists(%DocumentCommand{} = cmd, field, params) do
    param_list = cond do
      is_list(params) -> params
      true -> [params]
    end
    where = " where body -> '#{field}' ? $1"
    %{cmd | where: where, params: param_list}
  end

  @doc """
  Creates a SELECT command based on the assembled pipeline.
  """
  def select(%DocumentCommand{} = cmd) do
    sql = """
    select id, #{cmd.json_field}::text, created_at, updated_at
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
  def limit(%DocumentCommand{} = cmd, len), do: Moebius.Query.limit(cmd, len)
  @doc """
  Alias for Query offset
  """
  def offset(%DocumentCommand{} = cmd, len), do: Moebius.Query.offset(cmd, len)

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
  def sort(%DocumentCommand{} = cmd, cols, direction \\ :asc) do
    order_column = cond do
      is_atom(cols) -> Atom.to_string cols
      true -> cols
    end
    sort_dir = Atom.to_string direction
    %{cmd | order: " order by body -> '#{order_column}' #{sort_dir}"}
  end

  def decide_command(%DocumentCommand{} = cmd, doc) do
    cond do
      Map.has_key?(doc, :id) && doc.id !=nil -> update(cmd, Map.delete(doc, :id), doc.id)
      true -> insert(cmd,  Map.delete(doc, :id))
    end
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
  def searchable(%DocumentCommand{} = cmd, search_params) when is_list(search_params) do
    %{cmd | search_fields: search_params}
  end


  @doc """
  An alias for `delete/1`, removes a document based on the filter setup.
  """
  def remove(%DocumentCommand{} = cmd), do: delete(cmd)
  @doc """
  An alias for `delete/1`, removes a document based on the filter setup.
  """
  def remove(%DocumentCommand{} = cmd, pid) when is_pid(pid), do: delete(cmd, pid)
  @doc """
  An alias for `delete/2`, removes a document with the specified ID.
  """
  def remove(%DocumentCommand{} = cmd, id), do: delete(cmd, id)
  @doc """
  An alias for `delete/2`, removes a document with the specified ID.
  """
  def remove(%DocumentCommand{} = cmd, pid, id) when is_pid(pid), do: delete(cmd, pid, id)


  @doc """
  Deletes a document based on the filter (if any)
  """
  def delete(%DocumentCommand{} = cmd),  do: cmd |> delete_command
  @doc """
  Deletes a document based on the filter (if any)
  """
  def delete(%DocumentCommand{} = cmd, pid) when is_pid(pid),  do: cmd |> delete_command
  @doc """
  Deletes a document with the given id
  """
  def delete(%DocumentCommand{} = cmd, id), do: cmd |> delete_command(id)
  @doc """
  Deletes a document with the given id
  """
  def delete(%DocumentCommand{} = cmd, pid, id) when is_pid(pid), do: cmd |> delete_command(id)


  def insert(%DocumentCommand{} = cmd, doc) do
    doc = Map.delete(doc, :created_at) |> Map.delete(:updated_at)
    sql = """
    insert into #{cmd.table_name}(#{cmd.json_field})
    VALUES($1)
    RETURNING id, #{cmd.json_field}::text, created_at, updated_at;
    """
    %{cmd | sql: sql, params: [doc], type: :insert}
  end

  # def insert(%DocumentCommand{} = cmd, doc) when is_list(doc) or is_map(doc) do
  #   {:ok, encoded} = Poison.encode(doc)
  #   insert(cmd, encoded)
  # end

  def update(%DocumentCommand{} = cmd, change, id) when is_map(change) and is_integer(id) do
    #{:ok, encoded} = Poison.encode(change)
    #remove created/updated
    change = Map.delete(change, :created_at) |> Map.delete(:updated_at)

    sql = """
    update #{cmd.table_name}
    set #{cmd.json_field} = $1,
    updated_at = now()
    where id = #{id} returning id, #{cmd.json_field}::text, created_at, updated_at;
    """
    %{cmd | sql: sql, type: :update, params: [change]}
  end


  @doc """
  Finds a document based on ID using the Primary Key index. An optimized query for finding a single document.

  Example:

  ```
  return = db(:user_docs)
    |> find(12)
  ```
  """
  def find(%DocumentCommand{} = cmd, id) when is_integer id do
    #no need to param this, it's an integer
    sql = "select id, #{cmd.json_field}::text, created_at, updated_at from #{cmd.table_name} where id=#{id}"
    %{cmd | sql: sql}
  end


  @doc """
  Performs a highly-tuned Full Text query on the indexed `search` column. This is set on `save/3`.

  Example:

  ```
  users = db(:user_docs)
    |> search("test.com")
  ```
  """
  def search(%DocumentCommand{} = cmd, term) when is_bitstring(term)  do

    sql = """
    select id, #{cmd.json_field}::text, created_at, updated_at from #{cmd.table_name}
    where search @@ to_tsquery($1)
    order by ts_rank_cd(search,to_tsquery($1))  desc
    """

    %{cmd | sql: sql, params: [term]}
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
  def search(%DocumentCommand{} = cmd, for: term, in: fields) do
    terms = Enum.map_join(fields, ", ' ', ", &"body -> '#{Atom.to_string(&1)}'")

    sql = """
    select id, #{cmd.json_field}::text, created_at, updated_at from #{cmd.table_name}
    where to_tsvector(concat(#{terms})) @@ to_tsquery($1)
    order by ts_rank_cd(to_tsvector(concat(#{terms})),to_tsquery($1))  desc
    """

    %{cmd | sql: sql, params: [term]}

  end


  defp delete_command(%DocumentCommand{} = cmd, id) when is_integer(id) do
    sql = "delete from #{cmd.table_name} where id=#{id} returning id, body::text, created_at, updated_at"
    %{cmd | sql: sql, type: :delete}
  end

  defp delete_command(%DocumentCommand{} = cmd) do
    sql = "delete from #{cmd.table_name} #{cmd.where} returning id, body::text, created_at, updated_at;"
    %{cmd | sql: sql, type: :delete}
  end




end
