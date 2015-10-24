defmodule Moebius.DocumentQuery do

  @moduledoc """
  If you like your Postgres doing document goodness, then you'll want to use this interface
  """

  import Poison

  def db(table) when is_atom(table),
    do: db(Atom.to_string(table))

  def db(table),
    do: %Moebius.DocumentCommand{table_name: table}

  def contains(cmd, criteria) do
    map = Enum.into(criteria, %{})
    encoded = encode!(map)

    #TODO: Do we need to parameterize this? I don't think so
    where = " where #{cmd.json_field} @> '#{encoded}'"
    %{cmd | where: where, params: []}
  end

  def filter(cmd, criteria, params \\ []) when is_bitstring(criteria) do
    unless is_list(params) do
      params = [params]
    end
    where = " where #{criteria}"
    %{cmd | where: where, params: params}
  end

  def filter(cmd, field, operator, params) do
    unless is_list(params) do
      params = [params]
    end
    where = " where body -> '#{field}' #{operator} $1"
    %{cmd | where: where, params: params}
  end

  def exists(cmd, field, params) do
    unless is_list(params) do
      params = [params]
    end
    where = " where body -> '#{field}' ? $1"
    %{cmd | where: where, params: params}
  end

  def select(cmd) do
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

  def limit(cmd, length), do: Moebius.Query.limit(cmd, length)
  def offset(cmd, length), do: Moebius.Query.offset(cmd, length)
  def function(cmd, name, args), do: Moebius.Query.function(cmd, name, args)
  def sql_file(cmd, file, args), do: Moebius.Query.sql_file(cmd, file, args)

  def sort(cmd, cols, direction \\ :asc) do
    order_column = cols
    if is_atom(cols) do
      order_column = Atom.to_string cols
    end
    sort_dir = Atom.to_string direction
    %{cmd | order: " order by body -> '#{order_column}' #{sort_dir}"}
  end

  def update(cmd, change, id) when is_map(change) and is_integer(id) do
    {:ok, encoded} = JSON.encode(change)
    sql = """
    update #{cmd.table_name}
    set #{cmd.json_field} = '#{encoded}'
    where id = #{id} returning id, #{cmd.json_field}::text;
    """
    %{cmd | sql: sql, type: :update}
  end

  defp insert(cmd, doc) when is_bitstring(doc) do
    sql = """
    insert into #{cmd.table_name}(#{cmd.json_field})
    VALUES('#{doc}')
    RETURNING id, #{cmd.json_field}::text;
    """
    %{cmd | sql: sql, params: [doc], type: :insert}
  end

  defp insert(cmd, doc) when is_list(doc) or is_map(doc) do
    {:ok, encoded} = JSON.encode(doc)
    insert(cmd, encoded)
  end

  def create_document_table(cmd, doc) do
    sql = """
    create table #{cmd.table_name}(
      id serial primary key not null,
      body jsonb not null,
      search tsvector,
      created_at timestamptz not null default now(),
      updated_at timestamptz
    );
    """
    res = %Moebius.QueryCommand{sql: sql} |> Moebius.Runner.execute
    %Moebius.QueryCommand{sql: "create index idx_#{cmd.table_name}_search on #{cmd.table_name} using GIN(search);"} |> Moebius.Runner.execute
    %Moebius.QueryCommand{sql: "create index idx_#{cmd.table_name} on #{cmd.table_name} using GIN(body jsonb_path_ops);"} |> Moebius.Runner.execute

    cmd
  end

  def save(cmd, doc, search_params \\ []) do
    if is_list(doc),  do: doc =  Enum.into(doc, %{})

    res = cond do
      Map.has_key? doc, :id -> update(cmd, Map.delete(doc, :id), doc.id) |> execute(:single)
      true -> insert(cmd, doc) |> execute(:single)
    end

    res = cond do
      res == {:error, "relation \"#{cmd.table_name}\" does not exist"} -> create_document_table(cmd, doc) |> save(doc)
      true -> res
    end

    if is_list(search_params) && length(search_params) > 0 do
      terms = Enum.map_join(search_params, ", ' ', ", &"body -> '#{Atom.to_string(&1)}'")
      stoof = "update #{cmd.table_name} set search = to_tsvector(concat(#{terms})) where id=#{res.id}"
        |> Moebius.Query.run
    end

    res
  end


  def delete(cmd, id) when is_integer(id) do
    sql = "delete from #{cmd.table_name} where id=#{id} returning *"
    %{cmd | sql: sql, type: :delete}
  end

  def delete(cmd) do
    sql = "delete from #{cmd.table_name} #{cmd.where} returning *;"
    %{cmd | sql: sql, type: :delete}
  end

  def first(cmd) do
    res = cmd
      |> select
      |> execute(:single)
  end

  def search(cmd, term) when is_bitstring(term)  do

    sql = """
    select id, body from #{cmd.table_name}
  	where search @@ to_tsquery($1)
  	order by ts_rank_cd(search,to_tsquery($1))  desc
    """

    %{cmd | sql: sql, params: [term]}
      |> execute
  end

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


  def to_list(cmd),  do: all(cmd)

  def all(cmd) do
    cmd
      |> select
      |> execute
  end

  def run(cmd),  do: execute(cmd)
  def execute(cmd, opts \\ nil) do
    cmd
      |> Moebius.Runner.execute
      |> parse_json_column(cmd)
      |> return_results(opts)
  end

  defp return_results({:error, err}), do: {:error, err}
  defp return_results([results], :single), do: results
  defp return_results(results, _opt), do: results

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
