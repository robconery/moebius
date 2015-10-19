defmodule Moebius.Transformer do

  def get_first_result({:ok, res}) do
    cols = res.columns
    [first_row | _] = res.rows
    {:ok, cols, first_row }
  end

  def zip_columns_and_row({:ok, cols,row}) do
    {:ok, List.zip([cols,row])}
  end

  def create_map_from_list({:ok, list}) do
    {:ok, Enum.into(list, %{})}
  end

  def coerce_atoms({:ok, string_key_map}) do
    coerce_atoms string_key_map
  end

  def coerce_atoms(string_key_map) do
    atomized = for {key, val} <- string_key_map, into: %{}, do: {String.to_atom(key), val}
    {:ok, atomized}
  end

  def to_list({:error, err}), do: {:error, err}
  def to_list({:ok, res}) do

    listed = cond do
      res.rows ->  Enum.map res.rows, fn(r) ->
        List.zip([res.columns, r])
          |> coerce_atoms
        end
      true -> []
    end

    {:ok, listed}
  end

  def to_single({:error, err}), do: {:error, err}
  def to_single({:ok, res}) do
    get_first_result({:ok, res})
      |> zip_columns_and_row
      |> create_map_from_list
      |> coerce_atoms
  end

end
