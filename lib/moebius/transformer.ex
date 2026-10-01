defmodule Moebius.Transformer do
  @moduledoc """
  Turns query results into what Moebius returns: maps with atom keys, `{:ok, value}` or
  `{:error, message}`.
  """

  alias Moebius.{Error, Result}

  def format_ok_result(result), do: {:ok, result}

  def to_single({:ok, %Result{command: :delete, rows: nil, num_rows: count}}),
    do: {:ok, %{deleted: count}}

  def to_single({:ok, %Result{num_rows: 0}}), do: {:ok, nil}
  def to_single({:ok, %Result{rows: nil}}), do: {:ok, nil}
  def to_single({:error, _} = error), do: error_message(error)

  def to_single({:ok, %Result{}} = res) do
    {:ok, result_list} = to_list(res)
    result_list |> List.first() |> format_ok_result
  end

  def to_list({:ok, %Result{rows: nil}}), do: {:ok, []}
  def to_list({:error, _} = error), do: error_message(error)

  def to_list({:ok, %Result{rows: rows, columns: cols}}) do
    cols = atomize_columns(cols)
    {:ok, Enum.map(rows, &(cols |> Enum.zip(&1) |> Map.new()))}
  end

  # Column names become atom keys. Atoms are never garbage collected, so this is only safe
  # because column names are a bounded set: the columns of your own tables and queries.
  # sobelow_skip ["DOS.StringToAtom"]
  def atomize_columns(cols), do: Enum.map(cols, &String.to_atom/1)

  def from_json({:error, _} = error), do: error_message(error)
  def from_json({:ok, %Result{rows: nil}}), do: {:ok, []}

  def from_json({:ok, %Result{rows: rows}}) do
    keys = document_keys()
    {:ok, Enum.map(rows, &handle_row(&1, keys))}
  end

  def from_json({:error, _} = error, :single), do: error_message(error)
  def from_json({:ok, %Result{rows: nil}}, :single), do: {:ok, nil}

  def from_json({:ok, %Result{rows: rows}}, :single),
    do: {:ok, rows |> List.first() |> handle_row(document_keys())}

  defp handle_row(nil, _keys), do: nil

  # The row's own columns win over keys of the same name inside the document, so a body
  # that carries an "id" can't pass itself off as another document.
  defp handle_row([id, json, created_at, updated_at], keys) do
    json
    |> Jason.decode!(keys: keys)
    |> Map.put(:id, id)
    |> Map.put(:created_at, created_at)
    |> Map.put(:updated_at, updated_at)
  end

  # Documents are read as body::text. A key becomes an atom only if that atom already exists,
  # as every field your own code names does; any other key stays a string. Atoms are never
  # garbage collected, so documents whose keys come from users could fill the atom table.
  # `config :moebius, document_keys: :atoms` makes every key an atom, for documents you trust.
  defp document_keys do
    case Application.get_env(:moebius, :document_keys, :existing_atoms) do
      :existing_atoms ->
        &existing_atom/1

      :atoms ->
        :atoms

      other ->
        raise ArgumentError,
              "document_keys must be :existing_atoms or :atoms, got: #{inspect(other)}"
    end
  end

  defp existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> key
  end

  defp error_message({:error, %Error{message: message}}), do: {:error, message}
  defp error_message({:error, message}), do: {:error, message}
end
