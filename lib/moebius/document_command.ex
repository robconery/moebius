defmodule Moebius.DocumentCommand do
  defstruct [
    table_name: nil,
    type: :select,
    sql: nil,
    params: [],
    json_field: "body",
    where: "",
    order: "",
    limit: "",
    offset: "",
  ]
end
