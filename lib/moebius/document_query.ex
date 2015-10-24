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

  def insert(cmd, doc) when is_bitstring(doc) do
    sql = """
    insert into #{cmd.table_name}(#{cmd.json_field})
    VALUES('#{doc}')
    RETURNING id, #{cmd.json_field}::text;
    """
    %{cmd | sql: sql, params: [doc], type: :insert}
  end

  def insert(cmd, doc) when is_list(doc) or is_map(doc) do
    {:ok, encoded} = JSON.encode(doc)
    insert(cmd, encoded)
  end

  def save(cmd, doc) do
    cond do
      Map.has_key? doc, :id -> update(cmd, Map.delete(doc, :id), doc.id) |> execute(:single)
      true -> insert(cmd, doc) |> execute(:single)
    end
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

  def to_list(cmd),  do: all(cmd)

  def all(cmd) do
    cmd
      |> select
      |> execute
  end

  def run(cmd),  do: execute(cmd)

  def execute(cmd, opts \\ nil) do
      case Moebius.Runner.execute(cmd) do
        {:ok, res} -> parse_json_column({:ok, res}, cmd) 
          |> return_results(opts)
        {:error, "relation \"artists\" does not exist"}-> 
          cond do
            cmd.type == :insert || cmd.type == :update ->
              create_document_table(cmd)
              [new_doc | _] = cmd.params
              insert(cmd, new_doc) |> execute(opts)
            true -> raise "table #{cmd.table_name} is not defined"
          end
      end
  end

  def create_document_table(cmd) do
    sql = "create table #{cmd.table_name} (
      id serial primary key, 
      body jsonb, 
      created_at timestamptz not null default now(),
      updated_at timestamptz)"
    Moebius.Query.run(sql)
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
