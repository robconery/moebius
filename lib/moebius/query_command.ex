defmodule Moebius.QueryCommand do
  defstruct sql: nil, params: nil, table_name: nil, columns: nil, vals: nil, type: :select, sql: nil, where: "", order: "", limit: "", offset: "", where_columns: []
end
