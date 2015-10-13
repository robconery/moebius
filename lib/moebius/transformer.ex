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
    atom_keyed = for {key, val} <- string_key_map, into: %{}, do: {String.to_atom(key), val}
    {:ok, atom_keyed}
  end

  def map_list(cols, [head | tail], res) do
    zipped = List.zip [cols, head]
    mapped = Enum.into zipped, %{}

    {:ok, atomized} =  coerce_atoms({:ok, mapped})

    res = List.insert_at(res, length(res), atomized)
    map_list(cols, tail, res)
  end


  def map_list({:error, err}), do: {:error, err}
  def map_list({:ok, res}) do
    cols = res.columns
    rows = res.rows
    map_list res.columns, res.rows, []
  end

  def map_single({:error, err}), do: {:error, err}
  def map_single({:ok, res}) do
    get_first_result({:ok, res})
      |> zip_columns_and_row
      |> create_map_from_list
      |> coerce_atoms
  end

end
