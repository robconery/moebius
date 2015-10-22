defmodule Moebius.FullTextSearch do
  use ExUnit.Case
  import Moebius.Query

  test "a simple full text query" do

    {:ok, res} = :users
          |> db()
          |> search("Mike", [:first, :last, :email])
          |> run

    assert length(res) > 0
  end

end
