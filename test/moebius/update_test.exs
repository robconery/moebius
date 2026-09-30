defmodule Moebius.UpdateTest do
  use ExUnit.Case
  import Moebius.Query

  describe "update/2 SQL" do
    test "a basic update numbers params after the filter's" do
      cmd = db(:users) |> filter(id: 1) |> update(email: "after@test.com")

      assert cmd.sql == "update users set email = $2 where id = $1 returning *;"
      assert cmd.params == [1, "after@test.com"]
      assert cmd.type == :update
    end

    test "an empty update raises" do
      assert_raise ArgumentError, fn -> db(:users) |> filter(id: 1) |> update([]) end
    end

    test "with a string filter" do
      cmd = db(:users) |> filter("id > 100") |> update(email: "test@test.com")

      assert cmd.sql == "update users set email = $1 where id > 100 returning *;"
      assert cmd.params == ["test@test.com"]
    end

    test "with a string filter and params" do
      cmd = db(:users) |> filter("email LIKE %$1", "test") |> update(email: "ox@test.com")

      assert cmd.sql == "update users set email = $2 where email LIKE %$1 returning *;"
      assert cmd.params == ["test", "ox@test.com"]
    end

    test "with an 'in' filter" do
      cmd = db(:users) |> filter(:first, in: ["Super", "Mike"]) |> update(roles: ["newrole"])

      assert cmd.sql == "update users set roles = $3 where first IN($1, $2) returning *;"
      assert cmd.params == ["Super", "Mike", ["newrole"]]
    end

    test "with a '>' filter" do
      cmd = db(:users) |> filter(:order_count, gt: 5) |> update(roles: ["newrole"])

      assert cmd.sql == "update users set roles = $2 where order_count > $1 returning *;"
      assert cmd.params == [5, ["newrole"]]
    end
  end

  describe "running updates" do
    setup do
      Moebius.TestData.reset_users!()
      TestDb.run("truncate date_night restart identity")
      :ok
    end

    test "returns the updated row" do
      {:ok, user} = db(:users) |> insert(email: "before@test.com") |> TestDb.run()

      assert {:ok, %{id: id, email: "after@test.com"}} =
               db(:users)
               |> filter(id: user.id)
               |> update(email: "after@test.com")
               |> TestDb.run()

      assert id == user.id
    end

    test "returns nil when nothing matches" do
      assert {:ok, nil} =
               db(:users) |> filter(id: 999) |> update(email: "x@test.com") |> TestDb.run()
    end

    test "a timestamp column can be set from a NaiveDateTime" do
      {:ok, row} = TestDb.run("insert into date_night(date) values(now()) returning id", [])
      [%{id: id}] = row

      assert {:ok, %{date: %DateTime{} = date}} =
               db(:date_night)
               |> filter(id: id)
               |> update(date: ~U[2030-01-01 00:00:00Z])
               |> TestDb.run()

      assert date.year == 2030
    end
  end
end
