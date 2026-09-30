defmodule Moebius.FullTextSearchTest do
  use ExUnit.Case
  import Moebius.Query

  setup do
    Moebius.TestData.reset_users!()

    {:ok, mike} =
      db(:users)
      |> insert(first: "Mike", last: "Smith", email: "mike.smith@test.com")
      |> TestDb.run()

    {:ok, _} =
      db(:users) |> insert(first: "Jane", last: "Doe", email: "jane@test.com") |> TestDb.run()

    {:ok, mike: mike}
  end

  test "search/2 builds a ranked full text query" do
    cmd = db(:users) |> search(for: "Mike", in: [:first, :last])

    assert cmd.sql =~ "to_tsvector(concat(first, ' ',  last)) @@ websearch_to_tsquery($1)"
    assert cmd.sql =~ "order by rank desc"
    assert cmd.params == ["Mike"]
  end

  test "search/2 takes what a person types: several words, quotes, apostrophes", %{mike: mike} do
    assert {:ok, [%{id: id}]} =
             db(:users) |> search(for: "mike smith", in: [:first, :last]) |> TestDb.run()

    assert id == mike.id
    assert {:ok, []} = db(:users) |> search(for: "O'Brien", in: [:first, :last]) |> TestDb.run()
  end

  test "search/2 returns only the matching rows, with a rank", %{mike: mike} do
    assert {:ok, [%{id: id, rank: rank}]} =
             db(:users) |> search(for: "Mike", in: [:first, :last, :email]) |> TestDb.run()

    assert id == mike.id
    assert is_float(rank) and rank > 0
  end
end
