defmodule MoebiusTest do
  use ExUnit.Case
  #doctest Moebius
  import Moebius.Query

  setup do
    db(:users) |> insert(email: "flippy@test.com", first: "Flip", last: "Sullivan")
    {:ok, res: true}
  end

  test "returning single returns map" do
    assert %{email: _email, first: _first, id: _id, last: _last} =
      TestDb.single("select id, email, first, last from users limit 1")
  end

  test "returning multiple rows returns map list" do
    assert [%{email: _email, first: _first, id: _id, last: _last}] =
      TestDb.all "select id, email, first, last from users limit 1"
  end

end
