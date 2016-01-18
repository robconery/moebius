defmodule Moebius.Transformer do
  @moduledoc """
  The results that come back from Postgrex are in a bit of a convoluted form with string key maps that aren't terribly useful.
  This module restructures the results.
  """

  def to_list({:error, err}), do: {:error, err}

  #a simple pass-through query
  def to_list({:ok, num}),  do: num

  def to_list({:ok, cols, rows}) do
    for row <- rows, cols=atomize_column_names(cols), do: merge_columns_row(cols, row) |> to_map
  end

  def to_single({:error, err}), do: {:error, err}

  #a simple pass-through query
  def to_single({:ok, num}),  do: num

  def to_single({:ok, cols, rows}) do
    to_list({:ok, cols, rows}) |> List.first
  end

  def to_map(list) do
    list = Enum.map list, fn({k,v}) ->
      fixed = case v do
        :null -> nil
        v -> v
      end
      {k,fixed}
    end
    Enum.into(list, %{})
  end

  #GRRRRRRRRRRRRRRRRRRR
  def merge_columns_row(cols, row) do
    List.zip([cols, row])
  end

  def atomize_column_names(cols) do
    Enum.map cols, fn({:column, name, _, _, _, _}) ->
      String.to_atom(name)
    end
  end

end
