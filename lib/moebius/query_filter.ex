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

    Basic Select using 'IN':

    iex> import Moebius.Query
    iex> cmd = db(:users) |>
    ...>   filter(:name, in: ["phillip", "lela", "bender"]) |>
    ...>   select
    iex> cmd.sql
    "select * from users where name IN($1, $2, $3);"
    iex> cmd.params
    ["phillip", "lela", "bender"]

    Basic Select using 'NOT IN':

    iex> import Moebius.Query
    iex> cmd = db(:users) |>
    ...>   filter(:name, not_in: ["phillip", "lela", "bender"]) |>
    ...>   select
    iex> cmd.sql
    "select * from users where name NOT IN($1, $2, $3);"
    iex> cmd.params
    ["phillip", "lela", "bender"]

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
    ...>  select
    iex> cmd.sql
    "select * from users where email LIKE $1 and name NOT IN($2, $3, $4);"
    iex> cmd.params
    ["%test.com%", "phillip", "lela", "bender"]

  """

  defmacro __using__(_opts) do
    quote do
      def filter(cmd, criteria, params),
        do: unquote(__MODULE__).filter(cmd, criteria, params)

      def filter(cmd, criteria),
        do: unquote(__MODULE__).filter(cmd, criteria)
    end
  end

  def filter(cmd, criteria) when is_bitstring(criteria),
    do: filter(cmd, criteria, [])

  def filter(%{where: ""} = cmd, criteria) when is_list(criteria) do
    cols = Keyword.keys(criteria)
    vals = Keyword.values(criteria) |> Moebius.Transformer.from_time_struct

    {filters, _count} = Enum.map_reduce cols, 1, fn col, acc ->
      {"#{col} = $#{acc}", acc + 1}
    end

    %{cmd | params: vals, where: " where #{Enum.join(filters, " and ")}", where_columns: cols} end

  def filter(%{where: ""} = cmd, criteria, not_in: params) when is_list(params) do
    %{cmd | where: " where #{criteria} NOT IN(#{map_params(params)})", params: params}
  end

  def filter(%{where: ""} = cmd, criteria, in: params) when is_list(params) do
    %{cmd | where: " where #{criteria} IN(#{map_params(params)})", params: params}
  end

  def filter(%{where: ""} = cmd, criteria, params) when is_list(params) do
    params = Moebius.Transformer.from_time_struct(params)
    %{cmd | params: params, where: " where #{criteria}"}
  end

  def filter(cmd, criteria, in: params) when is_list(params) do
    current_params_length = cmd.params |> length

    in_list = map_params(params, current_params_length)
    predicates = join_predicates(cmd, "#{criteria} IN(#{in_list})")

    %{cmd | where: predicates, params: cmd.params ++ params}
  end

  def filter(cmd, criteria, not_in: params) when is_list(params) do
    current_params_length = cmd.params |> length

    in_list = map_params(params, current_params_length)
    predicates = join_predicates(cmd, "#{criteria} NOT IN(#{in_list})")

    %{cmd | where: predicates, params: cmd.params ++ params}
  end

  def filter(cmd, criteria, params) when not is_list(params),
    do: filter(cmd, criteria, [params])

  def filter(cmd, criteria, params) when is_list(params) do
    %{cmd | where: join_predicates(cmd, criteria), params: cmd.params ++ params}
  end

  def filter(cmd, criteria, params) when is_list(params),
    do: filter(cmd, criteria, params)

  defp map_params(params, seed \\ 0),
    do: Enum.map_join((seed + 1)..(length(params) + seed), ", ", &"$#{&1}")

  defp join_predicates(cmd, predicate),
    do: [cmd.where, predicate] |> Enum.join(" and ")

end
