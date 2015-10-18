defmodule Moebius.QueryCommand do
  defstruct sql: nil, params: nil, table_name: nil, columns: nil, vals: nil
end
