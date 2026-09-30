defmodule Moebius.FilterTest do
  use ExUnit.Case
  import Moebius.Query

  setup do
    Moebius.TestData.reset_users!()

    {:ok, _} =
      db(:users) |> insert(email: "named@test.com", first: "Ann", last: "Lee") |> TestDb.run()

    {:ok, _} = db(:users) |> insert(email: "anon@test.com", first: "Bo") |> TestDb.run()
    :ok
  end

  describe "nil" do
    test "a keyword nil is IS NULL and takes no parameter" do
      cmd = db(:users) |> filter(first: "Bo", last: nil, email: "anon@test.com")

      assert cmd.where == " where first = $1 and last is null and email = $2"
      assert cmd.params == ["Bo", "anon@test.com"]
      assert {:ok, [%{email: "anon@test.com"}]} = TestDb.run(cmd)
    end

    test "eq: nil and neq: nil" do
      assert {:ok, [%{email: "anon@test.com"}]} =
               db(:users) |> filter(:last, eq: nil) |> TestDb.run()

      assert {:ok, [%{email: "named@test.com"}]} =
               db(:users) |> filter(:last, neq: nil) |> TestDb.run()
    end

    test "nil after other filters keeps the numbering" do
      cmd =
        db(:users)
        |> filter("first = $1", "Bo")
        |> filter(last: nil)
        |> filter(:email, eq: "anon@test.com")

      assert cmd.where == " where first = $1 and last is null and email = $2"
      assert {:ok, [%{email: "anon@test.com"}]} = TestDb.run(cmd)
    end
  end

  describe "in" do
    test "an empty in: list matches nothing, and an empty not_in: matches everything" do
      assert {:ok, []} = db(:users) |> filter(:first, in: []) |> TestDb.run()
      assert {:ok, [_, _]} = db(:users) |> filter(:first, not_in: []) |> TestDb.run()
    end

    test "in: runs" do
      assert {:ok, [%{first: "Ann"}]} =
               db(:users) |> filter(:first, in: ["Ann", "Cy"]) |> TestDb.run()
    end
  end
end
