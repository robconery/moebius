defmodule Moebius.DateTest do
  use ExUnit.Case
  import Moebius.Query

  setup do
    TestDb.run("truncate date_night restart identity")
    :ok
  end

  test "timestamptz columns come back as DateTime structs" do
    {:ok, _} = TestDb.run("insert into date_night(date) values ('2026-02-03 04:05:06+00')")

    assert {:ok, %{date: %DateTime{} = date}} = db(:date_night) |> TestDb.first()
    assert DateTime.to_iso8601(date) == "2026-02-03T04:05:06.000000Z"
  end

  test "a DateTime can be used as a parameter" do
    {:ok, _} =
      db(:date_night)
      |> insert(date: ~U[2026-02-03 04:05:06.000000Z])
      |> TestDb.run()

    assert {:ok, %{count: 1}} =
             db(:date_night)
             |> filter("date = $1", ~U[2026-02-03 04:05:06.000000Z])
             |> count()
             |> TestDb.run()
  end

  test "null dates come back as nil" do
    {:ok, _} = TestDb.run("insert into date_night(date) values (null)")

    assert {:ok, %{date: nil}} = db(:date_night) |> TestDb.first()
  end
end
