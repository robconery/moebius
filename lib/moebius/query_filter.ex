defmodule Moebius.QueryFilter do
  @moduledoc """

  The QueryFilter module is used to build WHERE clauses to be used in queries. You can
  call it directly but in most cases it will be used through the Query module (see Query module).

  Here is an example of adding a predicate to match an email address:

    iex> cmd = %Moebius.QueryCommand{table_name: 'users'}
    iex> cmd = Moebius.QueryFilter.filter(cmd, email: "test@test.com")
    iex> cmd.where
    " where email = $1"
    iex> cmd.params
    ["test@test.com"]

  Or if you prefer a more SQL-like syntax, you can use "where", which is an alias for "filter":

    iex> cmd = Moebius.QueryFilter.where(cmd, email: "test@test.com")

  Although there are more examples in the Moebius.Query module here are a few to show filters in
  action:

    Basic Select:

    iex> import Moebius.Query
    iex> cmd = db(:users) |>
    ...>   filter(email: "test@test.com") |>
    ...>   select
    iex> cmd.sql
    "select * from users where email = $1;"
    iex> cmd.params
    ["test@test.com"]

    Basic Select using '>' Operator:

    iex> import Moebius.Query
    iex> cmd = db(:users) |>
    ...>   filter(:order_count, gt: 5) |>
    ...>   select
    iex> cmd.sql
    "select * from users where order_count > $1;"
    iex> cmd.params
    ["phillip", "lela", "bender"]

    Basic Select using 'IN' Operator:

    iex> import Moebius.Query
    iex> cmd = db(:users) |>
    ...>   filter(:name, in: ["phillip", "lela", "bender"]) |>
    ...>   select
    iex> cmd.sql
    "select * from users where name IN($1, $2, $3);"
    iex> cmd.params
    ["phillip", "lela", "bender"]

    All available Operators:

    - "=": eq
    - "!=": neq
    - ">": gt
    - "<": lt
    - ">=": gte
    - "<=": lte
    - "IN": in
    - "NOT IN": not_in (or nin)

    Basic Select using string:

    iex> import Moebius.Query
    iex> cmd = db(:users) |>
    ...>   filter("email LIKE $1", "%test.com%") |>
    ...>   select
    iex> cmd.sql
    "select * from users where email LIKE $1;"
    iex> cmd.params
    ["%test.com%"]

  Filters can also be piped:

    iex> import Moebius.Query
    iex> cmd = db(:users) |>
    ...>  filter("email LIKE $1", "%test.com%") |>
    ...>  filter(:name, not_in: ["phillip", "lela", "bender"]) |>
    ...>  filter(:order_count, gt: 5) |>
    ...>  select
    iex> cmd.sql
    "select * from users where email LIKE $1 and name NOT IN($2, $3, $4) and order_count > $5;"
    iex> cmd.params
    ["%test.com%", "phillip", "lela", "bender"]

  """

  defmacro __using__(_opts) do
    quote do
      def filter(cmd, criteria, params), do: unquote(__MODULE__).filter(cmd, criteria, params)
      def filter(cmd, criteria), do: unquote(__MODULE__).filter(cmd, criteria)

      defdelegate where(cmd, criteria, params), to: unquote(__MODULE__), as: :filter
      defdelegate where(cmd, criteria), to: unquote(__MODULE__), as: :filter
    end
  end

  def filter(cmd, criteria) when is_bitstring(criteria),
    do: filter(cmd, criteria, [])

  def filter(%{where: ""} = cmd, criteria) when is_list(criteria) do
    cols = Keyword.keys(criteria)
    vals = Keyword.values(criteria)

    {filters, _count} =
      Enum.map_reduce(cols, 1, fn col, acc ->
        {"#{col} = $#{acc}", acc + 1}
      end)

    %{cmd | params: vals, where: " where #{Enum.join(filters, " and ")}", where_columns: cols}
  end

  def filter(%{where_columns: existing} = cmd, criteria) when is_list(existing) do
    cols = Keyword.keys(criteria)
    vals = Keyword.values(criteria)
    param_seed = length(cmd.params) + 1

    {filters, _count} =
      Enum.map_reduce(cols, param_seed, fn col, acc ->
        {"#{col} = $#{acc}", acc + 1}
      end)

    # we have an existing filter, which means we need to append the params and "and" the where
    new_params = cmd.params ++ vals
    new_where = Enum.join([cmd.where, "and #{Enum.join(filters, " and ")}"], " ")
    new_cols = cmd.where_columns ++ cols

    %{cmd | params: new_params, where: new_where, where_columns: new_cols}
  end

  def filter(%{where: ""} = cmd, criteria, eq: param) when not is_list(param) do
    update_cmd(cmd, criteria, :eq, param)
  end

  def filter(%{where: ""} = cmd, criteria, neq: param) when not is_list(param) do
    update_cmd(cmd, criteria, :neq, param)
  end

  def filter(%{where: ""} = cmd, criteria, gt: param) when not is_list(param) do
    update_cmd(cmd, criteria, :gt, param)
  end

  def filter(%{where: ""} = cmd, criteria, lt: param) when not is_list(param) do
    update_cmd(cmd, criteria, :lt, param)
  end

  def filter(%{where: ""} = cmd, criteria, gte: param) when not is_list(param) do
    update_cmd(cmd, criteria, :gte, param)
  end

  def filter(%{where: ""} = cmd, criteria, lte: param) when not is_list(param) do
    update_cmd(cmd, criteria, :lte, param)
  end

  def filter(%{where: ""} = cmd, criteria, in: params) when is_list(params) do
    %{cmd | where: " where #{criteria} IN(#{map_params(params)})", params: params}
  end

  def filter(%{where: ""} = cmd, criteria, not_in: params) when is_list(params) do
    %{cmd | where: " where #{criteria} NOT IN(#{map_params(params)})", params: params}
  end

  def filter(%{where: ""} = cmd, criteria, nin: params) when is_list(params) do
    filter(cmd, criteria, not_in: params)
  end

  def filter(%{where: ""} = cmd, criteria, params) when is_list(params) do
    %{cmd | params: params, where: " where #{criteria}"}
  end

  def filter(cmd, criteria, eq: param) when not is_list(param) do
    update_predicates_cmd(cmd, criteria, :eq, param)
  end

  def filter(cmd, criteria, neq: param) when not is_list(param) do
    update_predicates_cmd(cmd, criteria, :neq, param)
  end

  def filter(cmd, criteria, gt: param) when not is_list(param) do
    update_predicates_cmd(cmd, criteria, :gt, param)
  end

  def filter(cmd, criteria, lt: param) when not is_list(param) do
    update_predicates_cmd(cmd, criteria, :lt, param)
  end

  def filter(cmd, criteria, gte: param) when not is_list(param) do
    update_predicates_cmd(cmd, criteria, :gte, param)
  end

  def filter(cmd, criteria, lte: param) when not is_list(param) do
    update_predicates_cmd(cmd, criteria, :lte, param)
  end

  def filter(cmd, criteria, in: params) when is_list(params) do
    in_list = map_params(params, length(cmd.params))
    predicates = join_predicates(cmd, "#{criteria} IN(#{in_list})")

    %{cmd | where: predicates, params: cmd.params ++ params}
  end

  def filter(cmd, criteria, not_in: params) when is_list(params) do
    in_list = map_params(params, length(cmd.params))
    predicates = join_predicates(cmd, "#{criteria} NOT IN(#{in_list})")

    %{cmd | where: predicates, params: cmd.params ++ params}
  end

  def filter(cmd, criteria, nin: params) when is_list(params) do
    filter(cmd, criteria, not_in: params)
  end

  def filter(cmd, criteria, params) when not is_list(params),
    do: filter(cmd, criteria, [params])

  def filter(cmd, criteria, params) when is_list(params) do
    %{cmd | where: join_predicates(cmd, criteria), params: cmd.params ++ params}
  end

  def filter(cmd, criteria, params) when is_list(params),
    do: filter(cmd, criteria, params)

  defdelegate where(cmd, criteria, params), to: __MODULE__, as: :filter
  defdelegate where(cmd, criteria), to: __MODULE__, as: :filter

  defp map_params(params, seed \\ 0),
    do: Enum.map_join((seed + 1)..(length(params) + seed), ", ", &"$#{&1}")

  defp join_predicates(cmd, predicate), do: [cmd.where, predicate] |> Enum.join(" and ")

  defp operator(:eq), do: "="
  defp operator(:neq), do: "!="
  defp operator(:gt), do: ">"
  defp operator(:lt), do: "<"
  defp operator(:gte), do: ">="
  defp operator(:lte), do: "<="

  defp update_cmd(cmd, criteria, oper, param) do
    where = " where #{criteria} #{operator(oper)} #{map_params([param])}"

    %{cmd | where: where, params: [param]}
  end

  defp update_predicates_cmd(cmd, criteria, oper, param) do
    in_list = map_params([param], length(cmd.params))
    where = join_predicates(cmd, "#{criteria} #{operator(oper)} #{in_list}")

    %{cmd | where: where, params: cmd.params ++ [param]}
  end
end
