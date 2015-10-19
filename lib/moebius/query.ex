defmodule Moebius.Query do

  def db(table, cols \\ "*") do
    %Moebius.QueryCommand{table_name: Atom.to_string(table), columns: cols}
  end

  def filter(cmd, criteria, not_in: params) when is_atom(criteria) and is_list(params) do
    #this is an IN query
    in_list = Enum.map_join(1..length(params), ", ", &"$#{&1}")
    where = " where #{Atom.to_string(criteria)} NOT IN(#{in_list})"
    %{cmd | where: where, params: params}
  end

  def filter(cmd, criteria, in: params) when is_atom(criteria) and is_list(params),  do: filter(cmd, criteria, params)
  def filter(cmd, criteria, params) when is_atom(criteria) and is_list(params) do
    #this is an IN query
    in_list = Enum.map_join(1..length(params), ", ", &"$#{&1}")
    where = " where #{Atom.to_string(criteria)} IN(#{in_list})"
    %{cmd | where: where, params: params}
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

  def select(cmd) do
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

  def sql_file(file, params \\ []) do

    unless is_list params do
      params = [params]
    end

    #find the DB dir
    scripts_dir = Application.get_env(:moebius, :scripts)
    file_path = Path.join(scripts_dir, "#{Atom.to_string(file)}.sql")
    sql=File.read!(file_path)

    %Moebius.QueryCommand{sql: String.strip(sql), params: params}
  end

  def run(cmd), do: Moebius.Runner.execute(cmd.sql, cmd.params)
  def execute(cmd), do: Moebius.Runner.execute(cmd.sql, cmd.params)
  def to_single(res), do: Moebius.Transformer.to_single(res)
  def to_list(res), do: Moebius.Transformer.to_list(res)

end
