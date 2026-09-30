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
  def from_json({:ok, %Result{rows: rows}}), do: {:ok, Enum.map(rows, &handle_row/1)}

  def from_json({:error, _} = error, :single), do: error_message(error)
  def from_json({:ok, %Result{rows: nil}}, :single), do: {:ok, nil}

  def from_json({:ok, %Result{rows: rows}}, :single),
    do: {:ok, rows |> List.first() |> handle_row()}

  defp handle_row(nil), do: nil

  defp handle_row([id, json, created_at, updated_at]) do
    json
    |> decode_json()
    |> Map.put_new(:id, id)
    |> Map.put_new(:created_at, created_at)
    |> Map.put_new(:updated_at, updated_at)
  end

  # documents are read as body::text; their keys are the document's own field names
  defp decode_json(json), do: Jason.decode!(json, keys: :atoms)

  defp error_message({:error, %Error{message: message}}), do: {:error, message}
  defp error_message({:error, message}), do: {:error, message}
end
