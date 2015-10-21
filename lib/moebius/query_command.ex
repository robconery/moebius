defmodule Moebius.QueryCommand do
  @moduledoc """
  Struct for the query command which is piped through all the transforms
  """
  defstruct [
      sql: nil, 
      params: nil,
      table_name: nil,
      columns: nil,
      vals: nil,
      type: :select,
      sql: nil,
      where: "",
      order: "",
      limit: "",
      offset: "",
      where_columns: [],
      join: [""]
    ]
end
