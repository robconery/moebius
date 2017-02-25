defmodule Moebius.Transformer do
  @moduledoc """
  The results that come back from Postgrex are in a bit of a convoluted form with string key maps that aren't terribly useful.
  This module restructures the results.
  """
  def format_ok_result(result), do: {:ok, result}

  def to_single({:ok, %{command: :delete, num_rows: count}}), do: {:ok, %{deleted: count}}
  def to_single({:ok, %{num_rows: count}}) when count == 0, do: {:ok, nil}
  def to_single({:error, message}) when is_binary(message), do: {:error, message}
  def to_single({:error, %{postgres: %{message: message}}}),  do: {:error, message}
  def to_single({:ok, %{rows: _rows, columns: _cols}} = res) do
    {:ok, result_list} = to_list(res)
    result_list |> List.first |> format_ok_result
  end

  def to_list({:ok, %{rows: nil}}), do: []
  def to_list({:error, message}) when is_binary(message), do: {:error, message}
  def to_list({:error, %{postgres: %{message: message}}}),  do: {:error, message}
  def to_list({:ok, %{rows: rows, columns: cols}}) do
    map_list = for row <- rows, cols = atomize_columns(cols), do: match_columns_to_row(row,cols) |> to_map
    format_ok_result(map_list)
  end

  def atomize_columns(cols), do: for col <- cols, do: String.to_atom(col)

  def match_columns_to_row(row, cols), do: List.zip([cols, row])
  def to_map(list) do
    Enum.into(list,%{})
  end

  def from_json({:error, err}), do: {:error, err}
  def from_json({:ok, res}) do
     res = Enum.map(res.rows, &handle_row/1)
     {:ok, res}
  end

  def from_json({:error, err}, _), do: {:error, err}
  def from_json({:ok, %{rows: rows}}, :single) do
    res = List.first(rows) |> handle_row
    {:ok, res}
  end

  defp handle_row(nil), do: nil

  defp handle_row([id, json, created_at, updated_at]) do
    json
      |> decode_json
      |> Map.put_new(:id, id)
      |> Map.put_new(:created_at, created_at)
      |> Map.put_new(:updated_at, updated_at)
  end

  #defp decode_json(json) when is_map(json), do: Moebius.Transformer.to_atom_map(json)
  defp decode_json(json), do: Poison.decode!(json, keys: :atoms)

end
