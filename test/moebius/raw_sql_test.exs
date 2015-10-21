defmodule MoebiusTest do
  use ExUnit.Case
  #doctest Moebius
  import Moebius.Runner

  test "returning single returns map" do
    assert %{email: _email, first: _first, id: _id, last: _last} =
      single("select id, email, first, last from users limit 1")
  end

  test "returning multiple rows returns map list" do
    assert [%{email: _email, first: _first, id: _id, last: _last}] =
      query "select id, email, first, last from users limit 1"
  end

end
