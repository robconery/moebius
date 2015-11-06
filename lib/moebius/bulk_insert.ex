#  defmodule Moebius.BulkInsert do
#   import Moebius.Query


#   def bulk_insert(cmd, records) do
#     transaction fn(pid) ->
#       bulk_insert_batch(cmd, records, [])
#       |> Enum.map(fn(cmd) -> 
#         execute_bulk(cmd, pid) end)
#       |> List.flatten        
#     end
#   end


#  defp bulk_insert_batch(cmd, records, acc) do
#     [first | rest] = records

#     # 20,000 seems to be the optimal number here. Technically you can go up to 34,464, but I think Postgrex imposes a lower limit, as I
#     # hit a wall at 34,000, but succeeded at 30,000. Perf on 100k records is best at 20,000. 
#     max_params = 20000 
#     cmd = %{ cmd | columns: Keyword.keys(first)}
#     max_records_per_command = div(max_params, length(cmd.columns))
    
#     { current, next_batch } = Enum.split(records, max_records_per_command)
#     this_cmd = bulk_insert_command(cmd, current)
#     case next_batch do
#       [] -> Enum.reverse([this_cmd | acc])
#       _ -> 
#         db(cmd.table_name) |> bulk_insert_batch(next_batch, [this_cmd | acc])
#     end
#   end


#   defp bulk_insert_command(cmd, [first | rest]) do
#     records = [first | rest]
#     cols = cmd.columns

#     vals = Enum.reduce(Enum.reverse(records), [], fn(listitem, acc) -> 
#     Enum.concat(Keyword.values(listitem), acc) end)

#     params_sql = elem(Enum.map_reduce(vals, 0, fn(v, acc) -> {"$#{acc + 1}", acc + 1} end),0)
#     |> Enum.chunk(length(cols))
#     |> Enum.map(fn(chunk) -> "(#{Enum.join(chunk, ", ")})" end)
#     |> Enum.join(", ")

#     sql_body = "insert into #{cmd.table_name} (" <> Enum.join(cols, ", ") <> ") " <>
#     "values #{ params_sql } returning *;"

#     %{cmd | columns: cols, sql: sql_body, params: vals, type: :insert}
#   end

#   defp execute_bulk(cmd, pid) do
#     Moebius.Runner.execute(cmd, pid)
#     |> Moebius.Transformer.to_list
#   end

# end