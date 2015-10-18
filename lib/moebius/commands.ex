
defmodule Moebius.Commands do

  def insert(map, table) do
    table_name = Atom.to_string table

    #grab the values from the map
    vals = Map.values(map)
    cols = Map.keys(map)

    sql = "INSERT INTO #{table}(" <> Enum.map_join(cols, ", ", &"#{&1}") <> ")" <>
    " VALUES(" <> Enum.map_join(1..length(cols), ", ", &"$#{&1}") <> ") RETURNING *;"

    %Moebius.QueryCommand{sql: sql, params: vals, table_name: table_name}
  end

  def insert([maps], table) do
    IO.puts "HOOHAA"
  end

end
