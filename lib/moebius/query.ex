defmodule Moebius.Query do

  def dataset(table, cols \\ "*") do
    %Moebius.QueryCommand{table_name: Atom.to_string(table), columns: cols}
  end

  def filter(cmd, criteria) when is_bitstring(criteria), do: filter(cmd, criteria, [])
  def filter(cmd, criteria, params) when is_bitstring(criteria)  do
    %{cmd | params: params}
    %{cmd | where: " where " <> criteria}
  end

  def filter(cmd, criteria) when is_list(criteria) do

    cols = Keyword.keys(criteria)
    vals = Keyword.values(criteria)

    {filters, _count} = Enum.map_reduce cols, 1, fn col, acc ->
      {"#{col} = $#{acc}", acc + 1}
    end

    where = " where " <> Enum.join(filters, " and ")

    %{cmd | params: vals}
    %{cmd | where: where}

  end

  def sort(cmd, cols, direction \\ :asc) do
    order_column = cols
    if is_atom(cols) do
      order_column = Atom.to_string cols
    end
    sort_dir = Atom.to_string direction
    %{cmd | order: " order by #{order_column} #{sort_dir}"}
  end

  def limit(cmd, bound) do
    %{cmd | limit: " limit #{bound}"}
  end

  def offset(cmd, skip) do
    %{cmd | offset: " offset #{skip}"}
  end

  def build(cmd, type: :select) do
    %{cmd | sql: "select #{cmd.columns} from #{cmd.table_name}#{cmd.where}#{cmd.order}#{cmd.limit}#{cmd.offset};"}
  end

end
