defmodule Moebius.AggregateTest do
  use ExUnit.Case
  import Moebius.Query

  test "count returns integer" do
    res = db(:users)
      |> count

    assert res > 1
  end

  test "sum returns integer for user ids" do
    sum = db(:users)
      |> map("id > 1")
      |> reduce(:sum, :id)
    assert sum > 1
  end

  test "sum returns integer for user ids grouped by email" do

    sum = db(:users)
      |> map("id > 1")
      |> group(:email)
      |> reduce(:sum, :id)

    assert sum > 1

  end

  test "reduce allows an expression" do

    sum = db(:users)
      |> map("id > 1")
      |> group(:email)
      |> reduce(:sum, "id + order_count")

    assert sum > 1

  end

end
