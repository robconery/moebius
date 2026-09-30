defmodule Moebius.CopyTest do
  use ExUnit.Case
  import Moebius.Query

  setup do
    TestDb.run("drop table if exists shipments")

    TestDb.run("""
    create table shipments(
      id int primary key,
      sku text not null,
      weight numeric(10,3),
      shipped_at timestamptz,
      tags text[],
      meta jsonb
    )
    """)

    :ok
  end

  defp shipment(n) do
    %{
      id: n,
      sku: "SKU-#{n}",
      weight: Decimal.new("#{n}.125"),
      shipped_at: ~U[2026-09-30 12:00:00.000000Z],
      tags: ["a", "b"],
      meta: %{n: n}
    }
  end

  defp count do
    {:ok, %{count: count}} = db(:shipments) |> count() |> TestDb.run()
    count
  end

  test "loads maps and returns the row count" do
    assert {:ok, 3} = TestDb.copy(:shipments, Enum.map(1..3, &shipment/1))

    assert {:ok,
            %{sku: "SKU-2", weight: weight, shipped_at: at, tags: ["a", "b"], meta: %{"n" => 2}}} =
             db(:shipments) |> filter(id: 2) |> TestDb.first()

    assert weight == Decimal.new("2.125")
    assert at == ~U[2026-09-30 12:00:00.000000Z]
  end

  test "loads keyword lists, in any key order" do
    rows = [[sku: "X", id: 1], [id: 2, sku: "Y"]]

    assert {:ok, 2} = TestDb.copy(:shipments, rows)
    assert {:ok, [%{sku: "X"}, %{sku: "Y"}]} = db(:shipments) |> sort(:id) |> TestDb.run()
  end

  test "streams a lazy enumerable in chunks" do
    rows = Stream.map(1..12_345, &shipment/1)

    assert {:ok, 12_345} = TestDb.copy(:shipments, rows, chunk: 1_000)
    assert count() == 12_345
  end

  test "an empty enumerable loads nothing" do
    assert {:ok, 0} = TestDb.copy(:shipments, [])
  end

  test ":columns picks and orders the columns; missing keys are NULL" do
    assert {:ok, 1} =
             TestDb.copy(:shipments, [%{id: 1, sku: "Z", ignored: "x"}],
               columns: [:id, :sku, :weight]
             )

    assert {:ok, %{sku: "Z", weight: nil}} = db(:shipments) |> TestDb.first()
  end

  test "a bad value is reported with its row and column, and nothing is written" do
    rows = [shipment(1), %{shipment(2) | weight: "heavy"}]

    assert {:error, "row 2, weight must be numeric, got: \"heavy\""} =
             TestDb.copy(:shipments, rows)

    assert count() == 0
  end

  test "a row the server rejects fails the whole copy" do
    rows = [shipment(1), shipment(1)]

    assert {:error, "duplicate key value violates unique constraint \"shipments_pkey\""} =
             TestDb.copy(:shipments, rows)

    assert count() == 0
  end

  test "the pool is healthy after a failed copy" do
    {:error, _} = TestDb.copy(:shipments, [%{id: "nope", sku: "x"}])
    {:error, _} = TestDb.copy(:shipments, [shipment(1), shipment(1)])

    assert {:ok, 1} = TestDb.copy(:shipments, [shipment(1)])
    assert %{in_use_count: 0} = TestDb.pool_status()
  end

  test "an unknown table or column is an error" do
    assert {:error, "relation \"nope\" does not exist"} = TestDb.copy(:nope, [%{id: 1}])

    assert {:error, "column \"colour\" does not exist"} =
             TestDb.copy(:shipments, [%{id: 1, colour: "red"}])
  end

  test "table and column names are checked" do
    assert_raise ArgumentError, fn -> TestDb.copy("shipments; drop table users", [%{id: 1}]) end
    assert_raise ArgumentError, fn -> TestDb.copy(:shipments, [%{"id) from stdin; --" => 1}]) end
  end

  test "joins an open transaction and rolls back with it" do
    assert {:error, :undo} =
             TestDb.transaction(fn _tx ->
               {:ok, 5} = TestDb.copy(:shipments, Enum.map(1..5, &shipment/1))
               assert count() == 5
               TestDb.rollback(:undo)
             end)

    assert count() == 0
  end
end
