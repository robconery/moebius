defmodule MoebiusTest do
  use ExUnit.Case
  #doctest Moebius
  import Moebius.Query

  test "returning single returns map" do
    assert %{email: _email, first: _first, id: _id, last: _last} =
      run("select id, email, first, last from users limit 1", :single)
  end

  test "returning multiple rows returns map list" do
    assert [%{email: _email, first: _first, id: _id, last: _last}] =
      run "select id, email, first, last from users limit 1"
  end

end
