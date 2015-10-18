
defmodule Moebius.Commands do

  def init_command(map, table) do
    table_name = Atom.to_string table

    #grab the values from the map
    vals = Map.values(map)
    cols = Map.keys(map)
    %Moebius.QueryCommand{params: vals, table_name: table_name, columns: cols, vals: vals}
  end

  def generate_sql(cmd, :insert) do

    Map.put_new cmd, :sql, "INSERT INTO #{cmd.table_name}(" <> Enum.map_join(cmd.columns, ", ", &"#{&1}") <> ")" <>
    " VALUES(" <> Enum.map_join(1..length(cmd.columns), ", ", &"$#{&1}") <> ") RETURNING *;"

  end

  def generate_sql(cmd, :update) do

    {fields, count} = Enum.map_reduce cmd.columns, 1, fn col, acc ->
      {"#{col} = $#{acc}", acc + 1}
    end

    {filters, _count} = Enum.map_reduce cmd.params, count, fn col, acc ->
      {"#{col} = $#{acc}", acc + 1}
    end

    "UPDATE #{cmd.table_name} SET " <> Enum.join(fields, ", ") <>
      " WHERE " <> Enum.join(filters, " AND ") <> " RETURNING *;"

  end

  def insert(map, table) do

    init_command(map, table)
      |> generate_sql(:insert)

  end

  def update(map, table) do
    init_command(map, table)
      |> generate_sql(:update)
  end

end
