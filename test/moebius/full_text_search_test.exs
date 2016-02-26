defmodule Moebius.FullTextSearch do
  use ExUnit.Case
  import Moebius.Query

  setup_all do
    res = db(:users)
      |> insert(first: "Mike", last: "Booger", email: "boogerbob@test.com")
      |> TestDb.run
    {:ok, user: res}
  end

  test "a simple full text query", %{user: user} do

    result = db(:users)
          |> search(for: user.first, in: [:first, :last, :email])
          |> TestDb.run

    assert length(result) > 0
  end

end
