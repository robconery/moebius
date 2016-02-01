defmodule Moebius.Transformer do
  @moduledoc """
  The results that come back from Postgrex are in a bit of a convoluted form with string key maps that aren't terribly useful.
  This module restructures the results.
  """
  import Poison

  def to_atom_map(map) do
    Enum.reduce(map, %{}, fn ({key, val}, acc) -> Map.put(acc, String.to_atom(key), val) end)
  end

  @doc """
  String keys are a pain, atom maps are nicer
  """
  def to_map(list, acc \\ %{})
  def to_map([], acc), do: acc
  def to_map([{key, val}|rest], acc) when is_list(val) do
    val = to_map(val, %{})
    acc = Map.put(acc, String.to_atom(key), [val])
    to_map(rest, acc)
  end
  def to_map([{key, val}|rest], acc) do
    acc = Map.put(acc, String.to_atom(key), val)
    to_map(rest, acc)
  end

  @doc """
  Coerce a large result set into an array of atom-keyed maps
  """
  def to_list({:error, err}), do: {:error, err}
  def to_list({:ok, %{rows: nil}}), do: []
  def to_list({:ok, %{rows: rows, columns: cols}}) do
    Enum.map rows, fn(r) ->
      {cols, r}
      |> zip_columns_and_row
      |> to_map
    end
  end

  @doc """
  Coerces a Postgrex.Result into a single atom-keyed map
  """
  def to_single({:error, err}), do: {:error, err}
  def to_single({:ok, %{command: :delete, num_rows: count}}),
    do: %{deleted: count}

  def to_single({:ok, %{num_rows: count}}) when count == 0,
    do: nil
  def to_single({:ok, %{num_rows: count} = res}) when count > 0 do
    res
    |> get_first_result
    |> zip_columns_and_row
    |> to_map
  end

  defp get_first_result(%{columns: cols, rows: rows}) do
    [first_row | _] = rows
    {cols, first_row}
  end

  defp zip_columns_and_row({cols, row}),
    do: List.zip([cols,row])


  def from_json({:error, err}, _), do: {:error, err}
  def from_json({:ok, res}) do
    Enum.map(res.rows, &handle_row/1)
  end
  def from_json({:ok, %Postgrex.Result{rows: rows}}, :single) do
    List.first(rows) |> handle_row
  end

  defp handle_row(nil), do: nil

  defp handle_row([id, json]) do
    json
    |> decode_json
    |> Map.put_new(:id, id)
  end

  #defp decode_json(json) when is_map(json), do: Moebius.Transformer.to_atom_map(json)
  defp decode_json(json), do: decode!(json, keys: :atoms)

end
