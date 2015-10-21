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
    %{cmd | sql: "select #{cmd.json_field}::text from #{cmd.table_name}#{cmd.where}#{cmd.order}#{cmd.limit}#{cmd.offset};"}
  end

  def insert(cmd, doc) when is_list(doc) do
    {:ok, encoded} = JSON.encode(doc)
    insert(cmd, encoded)
  end

  def insert(cmd, doc) when is_bitstring(doc) do
    sql = "insert into #{cmd.table_name}(#{cmd.json_field}) VALUES($1) RETURNING #{cmd.json_field};";
    %{cmd | sql: sql, params: [doc]}
  end

  def first(cmd) do
    cmd
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

  def execute(cmd) do
    cmd
      |> Moebius.Runner.execute
      |> parse_json_column(cmd)
  end

  defp parse_json_column({:error, err}), do: {:error, err}
  defp parse_json_column({:ok, res}, cmd) do
    cond do
      length(res.rows) > 0 -> {:ok, decode!(res.rows, keys: :atoms!)}
      true -> {:ok, []}
    end

  end


end
