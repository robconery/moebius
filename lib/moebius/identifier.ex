defmodule Moebius.Identifier do
  @moduledoc """
  Checks the table, column and function names Moebius puts into SQL.

  Values always travel as `$n` parameters, but Postgres can't take a name as a parameter,
  so names are written into the SQL text. Every name is checked first, and anything that
  isn't a plain name raises `ArgumentError` before any SQL is built.

  A plain name is letters, digits, `_` and `$`, starting with a letter or `_`, optionally
  qualified by a schema (`membership.users`). A double-quoted name (`"Order Items"`) is
  accepted too, as long as it contains no quote.

  Strings you pass as SQL fragments (`filter("price > $1", 10)`, `select("count(*) as n")`)
  are your own SQL and are used as written. Only pass trusted text there.
  """

  @part ~S/(?:[A-Za-z_][A-Za-z0-9_$]*|"[^"]+")/
  @name Regex.compile!("\\A#{@part}(?:\\.#{@part})?\\z")
  @script ~r/\A[A-Za-z0-9_\-]+(?:\/[A-Za-z0-9_\-]+)*\z/

  @doc """
  Returns the name as a string, or raises `ArgumentError`.

      iex> Moebius.Identifier.name!(:users)
      "users"
      iex> Moebius.Identifier.name!("membership.users")
      "membership.users"
      iex> Moebius.Identifier.name!("users; drop table users")
      ** (ArgumentError) invalid SQL identifier: "users; drop table users"
  """
  def name!(name) when is_atom(name) and not is_nil(name) and not is_boolean(name),
    do: name |> Atom.to_string() |> name!()

  def name!(name) when is_binary(name) do
    if Regex.match?(@name, name), do: name, else: invalid!(name)
  end

  def name!(name), do: invalid!(name)

  @doc "Checks every name in a list and joins them with `, `."
  def names!(names) when is_list(names), do: Enum.map_join(names, ", ", &name!/1)

  @doc """
  Quotes a JSON key as a SQL string literal, for `body -> 'key'`. Single quotes are doubled,
  so any key is safe.

      iex> Moebius.Identifier.json_key(:email)
      "'email'"
      iex> Moebius.Identifier.json_key("o'brien")
      "'o''brien'"
  """
  def json_key(key) when is_atom(key), do: key |> Atom.to_string() |> json_key()
  def json_key(key) when is_binary(key), do: "'" <> String.replace(key, "'", "''") <> "'"

  @doc "Returns the sort direction as SQL, or raises `ArgumentError`."
  def direction!(dir) when dir in [:asc, :desc], do: Atom.to_string(dir)

  def direction!(dir) when is_binary(dir) do
    case String.downcase(dir) do
      d when d in ["asc", "desc"] -> d
      _ -> raise ArgumentError, "sort direction must be :asc or :desc, got: #{inspect(dir)}"
    end
  end

  def direction!(dir),
    do: raise(ArgumentError, "sort direction must be :asc or :desc, got: #{inspect(dir)}")

  @doc "Checks a SQL file name: letters, digits, `_`, `-`, and `/` between folders. No `..`."
  def script!(name) when is_atom(name), do: name |> Atom.to_string() |> script!()

  def script!(name) when is_binary(name) do
    if Regex.match?(@script, name),
      do: name,
      else: raise(ArgumentError, "invalid SQL file name: #{inspect(name)}")
  end

  defp invalid!(name), do: raise(ArgumentError, "invalid SQL identifier: #{inspect(name)}")
end
