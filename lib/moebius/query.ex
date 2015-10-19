defmodule Moebius.Query do

  def dataset(table, cols \\ "*") do
    %Moebius.QueryCommand{table_name: Atom.to_string(table), columns: cols}
  end

  def filter(cmd, criteria) when is_bitstring(criteria), do: filter(cmd, criteria, [])
  def filter(cmd, criteria, params) when is_bitstring(criteria)  do
    unless is_list params do
      params = [params]
    end
    %{cmd | params: params, where: " where " <> criteria}
  end

  def filter(cmd, criteria) when is_list(criteria) do

    cols = Keyword.keys(criteria)
    vals = Keyword.values(criteria)

    {filters, _count} = Enum.map_reduce cols, 1, fn col, acc ->
      {"#{col} = $#{acc}", acc + 1}
    end

    where = " where " <> Enum.join(filters, " and ")

    %{cmd | params: vals, where: where, where_columns: cols}
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


  def insert(cmd, criteria) do
    cols = Keyword.keys(criteria)
    vals = Keyword.values(criteria)

    sql = "insert into #{cmd.table_name}(" <> Enum.map_join(cols, ", ", &"#{&1}") <> ")" <>
    " values(" <> Enum.map_join(1..length(cols), ", ", &"$#{&1}") <> ") returning *;"

    %{cmd | sql: sql, params: vals, type: :insert}
  end

  def update(cmd, criteria) when is_list(criteria) do
    cols = Keyword.keys(criteria)
    vals = Keyword.values(criteria)

    {cols, count} = Enum.map_reduce cols, 1, fn col, acc ->
      {"#{col} = $#{acc}", acc + 1}
    end

    #here's something for John to clean up :):)
    where = cond do

      length(cmd.where_columns) > 0 ->
        {filters, _count} = Enum.map_reduce cmd.where_columns, count, fn col, acc ->
          {"#{col} = $#{acc}", acc + 1}
        end
        " where " <> Enum.join(filters, " and ")

      cmd.where -> cmd.where
    end
    params = cond do
      length(cmd.params) > 0 && length(vals) > 0 ->
        List.flatten(vals,cmd.params)
      length(vals) > 0 -> vals
    end

    sql = "update #{cmd.table_name} set " <> Enum.join(cols, ", ") <> where <> " returning *;"
    %{cmd | sql: sql, type: :update, params: params}
  end

  def delete(cmd) do
    sql = "delete from #{cmd.table_name}" <> cmd.where <> " returning *;"
    %{cmd | sql: sql, type: :delete}
  end


end
