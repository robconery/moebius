defmodule Moebius.ReportedIssuesTest do
  use ExUnit.Case
  import Moebius.Query

  setup do
    Moebius.TestData.reset_users!()
    :ok
  end

  test "multiple filters are joined with and (#70)" do
    {:ok, _} =
      db(:users)
      |> insert(first: "Super", last: "Filter", email: "superfilter@test.com")
      |> TestDb.run()

    {:ok, _} =
      db(:users) |> insert(first: "Super", last: "Other", email: "other@test.com") |> TestDb.run()

    assert {:ok, [%{email: "superfilter@test.com"}]} =
             db(:users)
             |> filter(first: "Super")
             |> filter(last: "Filter")
             |> TestDb.run()
  end

  test "an array column can be updated (#80)" do
    {:ok, _} = db(:users) |> insert(email: "array@test.com", roles: ["admin"]) |> TestDb.run()

    assert {:ok, %{email: "array@test.com", roles: ["admin", "owner"]}} =
             db(:users)
             |> filter(email: "array@test.com")
             |> update(roles: ["admin", "owner"])
             |> TestDb.first()
  end

  test "filtering on nil matches NULL (#35)" do
    {:ok, _} = db(:users) |> insert(email: "null@test.com", first: "Test") |> TestDb.run()

    {:ok, _} =
      db(:users) |> insert(email: "notnull@test.com", first: "Test", last: "Set") |> TestDb.run()

    assert {:ok, [%{email: "null@test.com"}]} = db(:users) |> filter(last: nil) |> TestDb.run()
  end
end
