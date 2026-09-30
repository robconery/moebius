defmodule Moebius.StreamTest do
  use ExUnit.Case
  import Moebius.Query

  setup do
    TestDb.run("drop table if exists readings")
    TestDb.run("create table readings(id int primary key, value int not null)")
    TestDb.run("insert into readings select g, g * 10 from generate_series(1, 2500) g")
    :ok
  end

  test "streams every row, in chunks, as maps" do
    rows = db(:readings) |> sort(:id) |> TestDb.stream(chunk: 1000) |> Enum.to_list()

    assert length(rows) == 2500
    assert hd(rows) == %{id: 1, value: 10}
    assert List.last(rows) == %{id: 2500, value: 25_000}
  end

  test "is lazy: halting early gives the connection back" do
    assert [%{id: 1}, %{id: 2}, %{id: 3}] =
             db(:readings) |> sort(:id) |> TestDb.stream(chunk: 2) |> Enum.take(3)

    assert %{in_use_count: 0} = TestDb.pool_status()
  end

  test "works with filters and parameters" do
    total =
      db(:readings)
      |> filter(:value, gt: 24_900)
      |> TestDb.stream()
      |> Stream.map(& &1.value)
      |> Enum.sum()

    assert total ==
             24_910 + 24_920 + 24_930 + 24_940 + 24_950 + 24_960 + 24_970 + 24_980 + 24_990 +
               25_000
  end

  test "runs inside an open transaction and sees its writes" do
    TestDb.transaction(fn tx ->
      TestDb.run("insert into readings values (9999, 1)", tx)

      assert [%{id: 9999}] =
               db(:readings) |> filter(id: 9999) |> TestDb.stream() |> Enum.to_list()
    end)
  end

  test "streams documents" do
    TestDb.run("drop table if exists stream_docs")
    for n <- 1..5, do: {:ok, _} = Moebius.DocumentQuery.db(:stream_docs) |> TestDb.save(%{n: n})

    assert [1, 2, 3, 4, 5] =
             Moebius.DocumentQuery.db(:stream_docs)
             |> TestDb.stream(chunk: 2)
             |> Enum.map(& &1.n)
             |> Enum.sort()
  end

  test "an error in the query raises when the stream is read" do
    assert_raise Moebius.Error, ~r/does not exist/, fn ->
      "select * from no_such_table"
      |> then(&%Moebius.QueryCommand{sql: &1})
      |> TestDb.stream()
      |> Enum.to_list()
    end

    assert %{in_use_count: 0} = TestDb.pool_status()
  end
end
