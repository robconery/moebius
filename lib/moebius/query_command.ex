defmodule Moebius.QueryCommand do
  @moduledoc """
  Struct for the query command which is piped through all the transforms
  """
  defstruct [
      pid: nil,
      sql: nil,
      params: [],
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
      join: [""],
      group_by: nil,
      error: nil
    ]
end
