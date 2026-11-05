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

  test "limit, offset and sort piped after search are honored (#99)" do
    for n <- 1..3 do
      {:ok, _} =
        db(:users)
        |> insert(first: "Searchable", last: "Person #{n}", email: "search#{n}@test.com")
        |> TestDb.run()
    end

    assert {:ok, [_, _, _]} =
             db(:users) |> search(for: "Searchable", in: [:first]) |> TestDb.run()

    assert {:ok, [_, _]} =
             db(:users) |> search(for: "Searchable", in: [:first]) |> limit(2) |> TestDb.run()

    assert {:ok, [%{email: "search3@test.com"}]} =
             db(:users)
             |> search(for: "Searchable", in: [:first])
             |> sort(:id, :desc)
             |> limit(1)
             |> TestDb.run()

    assert {:ok, %{email: "search2@test.com"}} =
             db(:users)
             |> search(for: "Searchable", in: [:first])
             |> sort(:id)
             |> offset(1)
             |> limit(1)
             |> TestDb.first()
  end
end
