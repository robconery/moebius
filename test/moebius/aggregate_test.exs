defmodule Moebius.AggregateTest do
  use ExUnit.Case
  import Moebius.Query

  setup do
    Moebius.TestData.reset_users!()

    for {email, orders} <- [{"a@test.com", 1}, {"b@test.com", 2}, {"c@test.com", 3}] do
      {:ok, _} = db(:users) |> insert(email: email, order_count: orders) |> TestDb.run()
    end

    :ok
  end

  describe "count/1" do
    test "returns the number of matching rows as an integer" do
      assert {:ok, %{count: 3}} = db(:users) |> count() |> TestDb.run()
    end

    test "ignores sort, limit and offset, which don't apply to a count" do
      cmd = db(:users) |> sort(:email) |> limit(1) |> offset(1) |> count()

      assert cmd.sql == "select count(1) from users;"
      assert {:ok, %{count: 3}} = TestDb.run(cmd)
    end

    test "respects filters" do
      assert {:ok, %{count: 2}} =
               db(:users) |> filter("order_count > 1") |> count() |> TestDb.run()
    end
  end

  describe "map/2 and reduce/3" do
    test "sums a column over the mapped rows" do
      assert {:ok, %{sum: 5}} =
               db(:users)
               |> map("order_count > 1")
               |> reduce(:sum, :order_count)
               |> TestDb.first()
    end

    test "groups the rollup when group/2 is set" do
      {:ok, rows} =
        db(:users)
        |> map("order_count > 1")
        |> group(:email)
        |> reduce(:sum, :order_count)
        |> TestDb.run()

      assert Enum.sort_by(rows, & &1.email) == [
               %{email: "b@test.com", sum: 2},
               %{email: "c@test.com", sum: 3}
             ]
    end

    test "accepts an expression as the column" do
      {:ok, rows} =
        db(:users)
        |> map("order_count > 2")
        |> group(:email)
        |> reduce(:sum, "id + order_count")
        |> TestDb.run()

      assert [%{email: "c@test.com", sum: 6}] = rows
    end
  end
end
