defmodule Moebius.AggregateTest do
  use ExUnit.Case
  import Moebius.Query

  setup_all do
    "insert into users(email, first, last) values('aggs@test.com','Rob','Blah');"
    |> TestDb.run()

    {:ok, []}
  end

  test "count returns integer" do
    {:ok, res} =
      db(:users)
      |> count
      |> TestDb.run()

    assert is_integer(res.count)
  end

  test "sum returns integer for user ids" do
    {:ok, res} =
      db(:users)
      |> map("id > 1")
      |> reduce(:sum, :id)
      |> TestDb.first()

    assert res.sum > 1
  end

  test "sum returns integer for user ids grouped by email" do
    {:ok, res} =
      db(:users)
      |> map("id > 1")
      |> group(:email)
      |> reduce(:sum, :id)
      |> TestDb.run()

    assert length(res) > 0
  end

  test "reduce allows an expression" do
    {:ok, res} =
      db(:users)
      |> map("id > 1")
      |> group(:email)
      |> reduce(:sum, "id + order_count")
      |> TestDb.run()

    assert length(res) > 0
  end
end
