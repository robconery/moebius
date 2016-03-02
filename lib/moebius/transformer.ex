defmodule Moebius.Transformer do
  @moduledoc """
  The results that come back from Postgrex are in a bit of a convoluted form with string key maps that aren't terribly useful.
  This module restructures the results.
  """
  def to_single({:ok, %{command: :delete, num_rows: count}}), do: %{deleted: count}
  def to_single({:ok, %{num_rows: count}}) when count == 0, do: nil
  def to_single({:error, message}) when is_binary(message), do: {:error, message}
  def to_single({:error, %{postgres: %{message: message}}}),  do: {:error, message}
  def to_single({:ok, %{rows: _rows, columns: _cols}} = res) do
    to_list(res) |> List.first
  end

  def to_list({:ok, %{rows: nil}}), do: []
  def to_list({:error, message}) when is_binary(message), do: {:error, message}
  def to_list({:error, %{postgres: %{message: message}}}),  do: {:error, message}
  def to_list({:ok, %{rows: rows, columns: cols}}) do
    for row <- rows, cols = atomize_columns(cols), do: match_columns_to_row(row,cols) |> to_map
  end

  def atomize_columns(cols), do: for col <- cols, do: String.to_atom(col)

  def from_time_struct(vals) do
    Enum.map vals, fn(v) ->
      v = check_for_string_date(v)
      case v do
        #standard timex date
        %Timex.DateTime{} -> %Postgrex.Timestamp{year: v.year, month: v.month, day: v.day, hour: v.hour, min: v.minute, sec: v.second}

        #using Erlang :calendar
        {{year, month, day}, {hour, minute, second}} -> %Postgrex.Timestamp{year: year, month: month, day: day, hour: hour, min: minute, sec: second}

        #some sugar
        :now ->
          now = Timex.Date.now
          %Postgrex.Timestamp{year: now.year, month: now.month, day: now.day, hour: now.hour, min: now.minute, sec: now.second}

        :yesterday ->
          now = Timex.Date.now |> Timex.Date.shift(days: -1)
          %Postgrex.Timestamp{year: now.year, month: now.month, day: now.day, hour: now.hour, min: now.minute, sec: now.second}

        :tomorrow ->
          now = Timex.Date.now |> Timex.Date.shift(days: 1)
          %Postgrex.Timestamp{year: now.year, month: now.month, day: now.day, hour: now.hour, min: now.minute, sec: now.second}

        #more sugar
        {:add_days, days} ->
          date = Timex.Date.now |> Timex.Date.shift(days: days)
          %Postgrex.Timestamp{year: date.year, month: date.month, day: date.day, hour: date.hour, min: date.minute, sec: date.second}

        {:subtract_days, days} ->
          date = Timex.Date.now |> Timex.Date.shift(days: -days)
          %Postgrex.Timestamp{year: date.year, month: date.month, day: date.day, hour: date.hour, min: date.minute, sec: date.second}

        v -> v
      end
    end
  end

  def check_for_string_date(val) when not is_binary(val), do: val
  def check_for_string_date(val) when is_binary(val) do
    case Timex.DateFormat.parse(val, "{YYYY}-{_M}-{_D} {_h24}:{_m}:{_s}") do
      {:ok, date} -> date
      {:error, _err} -> val
    end
  end

  def match_columns_to_row(row, cols), do: List.zip([cols, row])
  def to_map(list) do
    Enum.into(list,%{})
  end



  def from_json({:error, err}), do: {:error, err}
  def from_json({:ok, res}) do
    Enum.map(res.rows, &handle_row/1)
  end

  def from_json({:error, err}, _), do: {:error, err}
  def from_json({:ok, %{rows: rows}}, :single) do
    List.first(rows) |> handle_row
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
