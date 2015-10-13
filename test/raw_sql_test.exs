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
      {:error, err} -> IO.inspect err#flunk err
    end
  end
end
