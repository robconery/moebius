defmodule Moebius.QueryFilter do

  defmacro __using__(_opts) do
    quote do
      def filter(cmd, criteria, params),
        do: unquote(__MODULE__).filter(cmd, criteria, params)

      def filter(cmd, criteria),
        do: unquote(__MODULE__).filter(cmd, criteria)
    end
  end

  @doc """
  A basic "WHERE" statement builder that builds a NOT IN statement using the supplied list.

  not_in:  -  a list of terms to exclude from the query

  Example:

  ```
  result = db(:users)
      |> filter(:name, not_in: ["mark", "biff", "skip"])
      |> to_list
  ```
  """
  def filter(cmd, criteria, not_in: params) when is_atom(criteria) and is_list(params) do
    #this is a NOT IN query
    in_list = Enum.map_join(1..length(params), ", ", &"$#{&1}")
    where = " where #{Atom.to_string(criteria)} NOT IN(#{in_list})"
    %{cmd | where: where, params: params}
  end

  @doc """
  Builds a parameterized WHERE statement based on the passed in string.
  This is useful for queries that pass in string information that you want to protect from SQL Injection.

  criteria  -   "name LIKE $1"
  params    -   "%steve%"
  Example:

  ```
  result = db(:products)
      |> filter("name LIKE %$1%", "steve")
      |> to_list
  ```
  """
  def filter(cmd, criteria, params) when not is_list(params),
    do: filter(cmd, criteria, [params])

  def filter(%{where: ""} = cmd, criteria, params) when is_bitstring(criteria),
    do: %{cmd | params: params, where: " where " <> criteria}

  @doc """
  A basic "WHERE" statement builder that builds an IN statement using the supplied list.

  in:  -  a list of terms to exclude from the query

  Example:

  ```
  result = db(:users)
      |> filter(:name, in: ["mark", "biff", "skip"])
      |> to_list
  ```
  """
  def filter(cmd, criteria, in: params) when is_atom(criteria) and is_list(params),
    do: filter(cmd, criteria, params)

  def filter(%{where: ""} = cmd, criteria, params) when is_atom(criteria) and is_list(params) do
    #this is an IN query
    in_list = Enum.map_join(1..length(params), ", ", &"$#{&1}")
    where = " where #{Atom.to_string(criteria)} IN(#{in_list})"
    %{cmd | where: where, params: params}
  end

  def filter(cmd, criteria, params) when is_atom(criteria) and is_list(params) do
    current_params_length = cmd.params |> length
    params_total_length = length(params) + current_params_length

    in_list = Enum.map_join((current_params_length + 1)..params_total_length, ", ", &"$#{&1}")
    where = "#{Atom.to_string(criteria)} IN(#{in_list})"
    conditions = [cmd.where, where] |> Enum.join(" and ")
    params = cmd.params ++ params

    %{cmd | where: conditions, params: params}
  end

  @doc """
  Builds a WHERE statement based on the passed in string. This is useful for ad-hoc queries, especially with
  date and time operations.

  criteria  -  "created_at > now()"

  Example:

  ```
  result = db(:products)
      |> filter("created_at > now()")
      |> to_list
  ```
  """
  def filter(cmd, criteria) when is_bitstring(criteria),
    do: filter(cmd, criteria, [])

  def filter(cmd, criteria, params) when is_bitstring(criteria) do
    params = cmd.params ++ params
    conditions = [cmd.where, criteria] |> Enum.join(" and ")
    %{cmd | params: params, where: conditions}
  end

  @doc """
  Builds a parameterized WHERE statement with ANDs for each passed list item.

  criteria  -   `email: 'test@test.com', company: 'Test Company'`

  Example:

  ```
  result = db(:products)
      |> filter(email: 'test@test.com', company: 'Test Company')
      |> to_list
  ```
  """
  def filter(cmd, criteria) when is_list(criteria) do

    cols = Keyword.keys(criteria)
    vals = Keyword.values(criteria)

    {filters, _count} = Enum.map_reduce cols, 1, fn col, acc ->
      {"#{col} = $#{acc}", acc + 1}
    end

    where = " where " <> Enum.join(filters, " and ")

    %{cmd | params: vals, where: where, where_columns: cols}
  end

end
