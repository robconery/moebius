defmodule Moebius.DateTests do
  use ExUnit.Case
  import Moebius.Query

  setup_all do
    res = "select * from date_night" |> TestDb.run
    {:ok, data: res}
  end

  test "Dates are transformed to Times", %{data: [ %{id: id, date: date} | _rest]} do
    assert is_binary(date)
  end

  test "adding a date works happily with Timex" do
    res = db(:date_night)
      |> insert(date: Timex.Date.now)
      |> TestDb.run

    assert is_binary(res.date)
  end

  test "updating a date works happily with :calendar" do

    res = db(:date_night)
      |> filter(id: 1)
      |> update(date: :calendar.local_time)
      |> TestDb.run

    assert is_binary(res.date)
  end

  test "updating a date works with :now" do

    res = db(:date_night)
      |> filter(id: 1)
      |> update(date: :now)
      |> TestDb.run

    assert is_binary(res.date)
  end

  test "using :add_days" do

    res = db(:date_night)
      |> filter(id: 1)
      |> update(date: {:add_days, 4})
      |> TestDb.run

    assert is_binary(res.date)
  end
  test "using :subtract_days" do

    res = db(:date_night)
      |> filter(id: 1)
      |> update(date: {:subtract_days, 4})
      |> TestDb.run

    assert is_binary(res.date)
  end

  test "using :tomorrow" do

    res = db(:date_night)
      |> filter(id: 1)
      |> update(date: :tomorrow)
      |> TestDb.run

    assert is_binary(res.date)
  end
  test "using :yesterday" do

    res = db(:date_night)
      |> filter(id: 1)
      |> update(date: :yesterday)
      |> TestDb.run

    assert is_binary(res.date)
  end
end
