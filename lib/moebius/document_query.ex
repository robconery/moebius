defmodule Moebius.DocumentQuery do

  import Poison

  def db(table) when is_atom(table),
    do: db(Atom.to_string(table))

  def db(table),
    do: %Moebius.DocumentCommand{table_name: table}

  def contains(cmd, criteria) do
    map = Enum.into(criteria, %{})
    encoded = encode!(map)

    #TODO: Do we need to parameterize this?
    where = " where #{cmd.json_field} @> '#{encoded}'"
    %{cmd | where: where, params: []}
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
    cmd = %{cmd | sql: sql, params: [doc], type: :insert}
  end

  def insert(cmd, doc) when is_list(doc) or is_map(doc) do
    {:ok, encoded} = JSON.encode(doc)
    insert(cmd, encoded)
  end

  def single(cmd) do
    res = cmd
      |> select
      |> execute

  end

  def all(cmd) do
    cmd
      |> select
      |> execute
  end

  def run(cmd) do
    cmd
      |> Moebius.Runner.execute
      |> parse_json_column(cmd)
  end

  def execute(cmd, opts \\ nil) do
    cmd
      |> Moebius.Runner.execute
      |> parse_json_column(cmd)
      |> return_results(opts)
  end

  defp return_results([results], :single), do: results
  defp return_results(results, _opt), do: results

  defp parse_json_column({:error, err}), do: {:error, err}
  defp parse_json_column({:ok, res}, cmd) do
    Enum.map(res.rows, &handle_row/1)
  end

  defp handle_row([id, json]) do
    decode_json(json) |> Map.put_new(:id, id)
  end

  defp decode_json(json) when is_map(json), do: json
  defp decode_json(json), do: decode!(json, keys: :atoms!)

end
