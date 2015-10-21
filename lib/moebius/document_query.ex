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
    %{cmd | sql: "select id, #{cmd.json_field}::text from #{cmd.table_name}#{cmd.where}#{cmd.order}#{cmd.limit}#{cmd.offset};"}
  end

  def insert(cmd, doc) when is_bitstring(doc) do
    sql = "insert into #{cmd.table_name}(#{cmd.json_field}) VALUES('#{doc}') RETURNING id, #{cmd.json_field};";
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
    res = cmd
      |> Moebius.Runner.execute
      |> parse_json_column(cmd)

    cond do
      opts == :single ->
        {:ok, [single]} = res
        {:ok, single}
      true -> res
    end

  end

  defp parse_json_column({:error, err}), do: {:error, err}
  defp parse_json_column({:ok, res}, cmd) do

    massaged = Enum.map res.rows, fn(row)->
      [id, json] = row
      decoded = decode!(json, keys: :atoms!)
      Map.put_new decoded, :id, id
    end

    {:ok, massaged}
  end


end
