defmodule Moebius.FullTextSearch do
  use ExUnit.Case
  import Moebius.Query

  test "a simple full text query" do

    result = db(:users)
          |> search(for: "Mike", in: [:first, :last, :email])
          |> to_list

    assert length(result) > 0
  end

end
