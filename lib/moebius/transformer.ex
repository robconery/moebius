defmodule Moebius.Transformer do

  def get_first_result(res) do
    cols = res.columns
    [first_row | _] = res.rows
    {cols, first_row}
  end

  def zip_columns_and_row({cols, row}) do
    List.zip([cols,row])
  end

  def create_map_from_list(list) do
    Enum.into(list, %{})
  end

  def coerce_atoms(string_key_map) do
    for {key, val} <- string_key_map, into: %{}, do: {String.to_atom(key), val}
  end

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

  def to_single({:error, err}), do: {:error, err}
  def to_single({:ok, res}) do
    get_first_result(res)
      |> zip_columns_and_row
      |> create_map_from_list
      |> coerce_atoms
  end

end
