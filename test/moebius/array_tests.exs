defmodule Moebius.ArrayTests do
  use ExUnit.Case
  import Moebius.Query

  #from #80
  setup_all do

    db(:users)
      |> insert(email: "array@test.com", first: "Test", last: "User", roles: ["admin"])
      |> TestDb.run

    {:ok, res: true}
  end

  test "It can update an array column" do
    res = db(:users)
      |> filter(email: "array@test.com")
      |> update(roles: ["admin"])
      |> TestDb.run

    IO.inspect res
  end
end
