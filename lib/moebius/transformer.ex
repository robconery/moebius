defmodule Moebius.Transformer do
  @moduledoc """
  The results that come back from Postgrex are in a bit of a convoluted form with string key maps that aren't terribly useful.
  This module restructures the results.
  """

  @doc """
  Returns the first result from a Postgrex.Result
  """
  def get_first_result(res) do
    cols = res.columns
    [first_row | _] = res.rows
    {cols, first_row}
  end

  @doc """
  Pushes the columns and rows together
  """
  def zip_columns_and_row({cols, row}) do
    List.zip([cols,row])
  end

  @doc """
  We want a map as a result, so let's make one
  """
  def create_map_from_list(list) do
    Enum.into(list, %{})
  end

  @doc """
  String keys are a pain, atom maps are nicer
  """
  def coerce_atoms(string_key_map) do
    for {key, val} <- string_key_map, into: %{}, do: {String.to_atom(key), val}
  end

  @doc """
  Coerce a large result set into an array of atom-keyed maps
  """
  def to_list({:error, err}), do: {:error, err}
  def to_list({:ok, res}) do
    cond do
      res.rows ->  Enum.map res.rows, fn(r) ->
        List.zip([res.columns, r])
          |> coerce_atoms
        end
      true -> []
    end
  end

  @doc """
  Coerces a Postgrex.Result into a single atom-keyed map
  """
  def to_single({:error, err}), do: {:error, err}
  def to_single({:ok, res}) do

    cond do
      res.command == :delete -> %{deleted: res.num_rows}
      res.num_rows > 0 ->
        get_first_result(res)
          |> zip_columns_and_row
          |> create_map_from_list
          |> coerce_atoms

      true -> []
    end

  end

end
