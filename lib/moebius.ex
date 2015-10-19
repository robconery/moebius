defmodule Moebius do

  def dataset(table) do

    %Moebius.QueryCommand{table_name: Atom.to_string(table)}

  end

  def where(condition) do

  end

end
