defmodule Moebius.RawSqlTest do
  use ExUnit.Case
  #doctest Moebius
  import Moebius.Query

  setup do
    db(:users) |> insert(email: "flippy@test.com", first: "Flip", last: "Sullivan")
    {:ok, res: true}
  end

  test "returning multiple rows returns map list" do
    assert [%{email: _email, first: _first, id: _id, last: _last}] =
      "select id, email, first, last from users limit 1" |> TestDb.run
  end

end
