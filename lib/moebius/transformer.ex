defmodule Moebius.Transformer do
  @moduledoc """
  The results that come back from Postgrex are in a bit of a convoluted form with string key maps that aren't terribly useful.
  This module restructures the results.
  """
  def to_single({:ok, %{command: :delete, num_rows: count}}), do: %{deleted: count}
  def to_single({:ok, %{num_rows: count}}) when count == 0, do: nil
  def to_single({:error, message}) when is_binary(message), do: {:error, message}
  def to_single({:error, %{postgres: %{message: message}}}),  do: {:error, message}
  def to_single({:ok, %{rows: rows, columns: cols}} = res) do
    IO.inspect "HI"
    to_list(res) |> List.first
  end

  def to_list({:ok, %{rows: nil}}), do: []
  def to_list({:error, message}) when is_binary(message), do: {:error, message}
  def to_list({:error, %{postgres: %{message: message}}}),  do: {:error, message}
  def to_list({:ok, %{rows: rows, columns: cols}}) do
    for row <- rows, cols = atomize_columns(cols), do: to_timex(row) |> match_columns_to_row(cols) |> to_map
  end

  def atomize_columns(cols), do: for col <- cols, do: String.to_atom(col)

  def from_timex(vals) do
    Enum.map vals, fn(v) ->
      case v do
        %Timex.DateTime{} -> %Postgrex.Timestamp{year: v.year, month: v.month, day: v.day, hour: v.hour, min: v.minute, sec: v.second}
        v -> v
      end
    end
  end

  def to_timex(row) do
    Enum.map row, fn(v) ->
      case v do
        #Postgrex.Timestamp{} -> %Timex.DateTime{year: v.year, month: v.month, day: v.day, hour: v.hour, minute: v.min, second: v.sec}
        %Postgrex.Timestamp{} -> "#{v.year}-{v.month}-#{v.day} #{v.hour}:#{v.min}:#{v.sec}"
        v -> v
      end
    end
  end

  def match_columns_to_row(row, cols), do: List.zip([cols, row])
  def to_map(list) do
    res = Enum.into(list,%{})
  end

  def from_json({:error, err}), do: {:error, err}
  def from_json({:error, err}, _), do: {:error, err}
  def from_json({:ok, res}) do
    Enum.map(res.rows, &handle_row/1)
  end
  def from_json({:ok, %{rows: rows}}, :single) do
    List.first(rows) |> handle_row
  end

  defp handle_row(nil), do: nil

  defp handle_row([id, json]) do
    json
    |> decode_json
    |> Map.put_new(:id, id)
  end

  #defp decode_json(json) when is_map(json), do: Moebius.Transformer.to_atom_map(json)
  defp decode_json(json), do: Poison.decode!(json, keys: :atoms)

end
