defmodule Moebius.QueryFilter do
  @moduledoc """

  The QueryFilter module is used to build WHERE clauses to be used in queries. You can
  call it directly but in most cases it will be used through the Query module (see Query module).

  Here is an example of adding a predicate to match an email address:

    iex> cmd = %Moebius.QueryCommand{table_name: "users"}
    iex> cmd = Moebius.QueryFilter.filter(cmd, email: "test@test.com")
    iex> cmd.where
    " where email = $1"
    iex> cmd.params
    ["test@test.com"]

  Or if you prefer a more SQL-like syntax, you can use "where", which is an alias for "filter":

    iex> cmd = %Moebius.QueryCommand{table_name: "users"}
    iex> cmd = Moebius.QueryFilter.where(cmd, email: "test@test.com")
    iex> cmd.where
    " where email = $1"

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
    [5]

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
    ["%test.com%", "phillip", "lela", "bender", 5]

  """

  defmacro __using__(_opts) do
    quote do
      def filter(cmd, criteria, params), do: unquote(__MODULE__).filter(cmd, criteria, params)
      def filter(cmd, criteria), do: unquote(__MODULE__).filter(cmd, criteria)

      defdelegate where(cmd, criteria, params), to: unquote(__MODULE__), as: :filter
      defdelegate where(cmd, criteria), to: unquote(__MODULE__), as: :filter
    end
  end

  alias Moebius.Identifier

  @operators [eq: "=", neq: "!=", gt: ">", lt: "<", gte: ">=", lte: "<="]

  def filter(cmd, criteria) when is_bitstring(criteria),
    do: filter(cmd, criteria, [])

  # nothing to filter on: the command is unchanged
  def filter(cmd, []), do: cmd

  # keyword criteria: equality, joined with and. nil means IS NULL and takes no parameter.
  def filter(cmd, criteria) when is_list(criteria) do
    {predicates, params} =
      Enum.reduce(criteria, {[], cmd.params}, fn
        {col, nil}, {preds, params} ->
          {["#{Identifier.name!(col)} is null" | preds], params}

        {col, value}, {preds, params} ->
          {["#{Identifier.name!(col)} = $#{length(params) + 1}" | preds], params ++ [value]}
      end)

    %{
      cmd
      | params: params,
        where: join_predicates(cmd, predicates |> Enum.reverse() |> Enum.join(" and ")),
        where_columns: cmd.where_columns ++ Keyword.keys(criteria)
    }
  end

  def filter(cmd, criteria, [{op, nil}]) when op in [:eq, :neq] do
    null_check = if op == :eq, do: "is null", else: "is not null"
    %{cmd | where: join_predicates(cmd, "#{column(criteria)} #{null_check}")}
  end

  def filter(cmd, criteria, [{op, param}])
      when is_map_key(%{eq: 1, neq: 1, gt: 1, lt: 1, gte: 1, lte: 1}, op) and not is_list(param) do
    placeholder = "$#{length(cmd.params) + 1}"
    predicate = "#{column(criteria)} #{@operators[op]} #{placeholder}"

    %{cmd | where: join_predicates(cmd, predicate), params: cmd.params ++ [param]}
  end

  def filter(cmd, criteria, in: params) when is_list(params),
    do: in_list(cmd, criteria, "IN", params)

  def filter(cmd, criteria, not_in: params) when is_list(params),
    do: in_list(cmd, criteria, "NOT IN", params)

  def filter(cmd, criteria, nin: params) when is_list(params),
    do: in_list(cmd, criteria, "NOT IN", params)

  def filter(cmd, criteria, params) when not is_list(params),
    do: filter(cmd, criteria, [params])

  # a SQL fragment with its own $n placeholders
  def filter(cmd, criteria, params) when is_binary(criteria) and is_list(params) do
    %{cmd | where: join_predicates(cmd, criteria), params: cmd.params ++ params}
  end

  defdelegate where(cmd, criteria, params), to: __MODULE__, as: :filter
  defdelegate where(cmd, criteria), to: __MODULE__, as: :filter

  @doc false
  # Keep an existing OR expression grouped when another builder adds a condition.
  def append_condition(cmd, predicate, params) do
    where =
      case cmd.where do
        "" -> " where #{predicate}"
        " where " <> existing -> " where (#{existing}) and #{predicate}"
      end

    %{cmd | where: where, params: cmd.params ++ params}
  end

  # IN () is a syntax error; nothing is in an empty list
  defp in_list(cmd, _criteria, "IN", []), do: %{cmd | where: join_predicates(cmd, "false")}
  defp in_list(cmd, _criteria, "NOT IN", []), do: %{cmd | where: join_predicates(cmd, "true")}

  defp in_list(cmd, criteria, op, params) do
    seed = length(cmd.params)
    placeholders = Enum.map_join((seed + 1)..(seed + length(params)), ", ", &"$#{&1}")

    %{
      cmd
      | where: join_predicates(cmd, "#{column(criteria)} #{op}(#{placeholders})"),
        params: cmd.params ++ params
    }
  end

  # a column given as an atom is a name and is checked; a string is an expression, used as is
  defp column(col) when is_atom(col), do: Identifier.name!(col)
  defp column(col) when is_binary(col), do: col

  defp join_predicates(%{where: ""}, predicate), do: " where #{predicate}"
  defp join_predicates(%{where: where}, predicate), do: "#{where} and #{predicate}"
end
