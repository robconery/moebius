defmodule MoebiusTest do
  use ExUnit.Case
  #doctest Moebius
  #import Moebius.Runner

  setup_all do
    Moebius.Runner.execute "delete from users;"
    {:ok, []}
  end

  test "inserting to users with raw SQL" do
    case Moebius.Runner.execute "insert into users(email) values ($1)", ["test@test.com"] do
      {:ok, res} -> assert res
      {:error, err} -> flunk IO.inspect(err)
    end
  end

  test "returning single returns map" do
    case Moebius.Runner.single "select id, email, first, last from users limit 1" do
      {:ok, res} -> assert res.id
      {:error, err} -> flunk IO.inspect(err)
    end
  end

end
