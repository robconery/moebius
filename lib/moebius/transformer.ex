defmodule Moebius.Transformer do
  require Logger

  def to_list({:error, err}), do: {:error, err}

  #a simple pass-through query
  def to_list({:ok, num}),  do: num

  def to_list({:ok, cols, rows}) do
    for row <- rows, do: merge_col_to_row(cols, row)
  end

  def merge_col_to_row(cols, data) do
    data = Tuple.to_list(data)
    for {{:column, name, type, _, _, _, _},idx} <- Enum.with_index(cols) do
      data = Enum.at(data,idx) |> convert(type)
      {String.to_atom(name),data}
    end |> to_map
  end
  def convert(data,type) do
    Logger.debug type
    case {type,data} do
      {:inet,{first, second, third, fourth}} -> "#{first},#{second},#{third},#{fourth}" #inet
      {:date, {year, month, day}} -> "#{year}-#{month}-#{day}"
      {:time, {hour, minute, second}} -> "#{hour}:#{minute}::#{second}"
      {:timestamp, {{year, month, day}, {hour, minute, second}}} -> "#{year}-#{month}-#{day} #{hour}:#{minute}::#{second}"
      {:timestamptz, {{year, month, day}, {hour, minute, second}}} -> "#{year}-#{month}-#{day} #{hour}:#{minute}::#{second}"
      {_, thing} -> thing
    end
  end
  def to_single({:error, err}), do: {:error, err}

  #a simple pass-through query
  def to_single({:ok, num}),  do: num

  def to_single({:ok, cols, rows}) do
    to_list({:ok, cols, rows}) 
    |> List.first
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

end