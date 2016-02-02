defmodule Moebius.DateTests do
  use ExUnit.Case
  import Moebius.Query

  setup_all do
    res = "select * from date_night" |> TestDb.all

    {:ok, data: res}
  end

  test "Dates are transformed to Times", %{data: [ %{id: id, date: %Timex.DateTime{} = date} | _rest]} do
    assert date.year == 2016
  end

  test "adding a date works happily" do
    res = db(:date_night)
      |> insert(date: Timex.Date.now)
      |> TestDb.run
    assert res.date.year == 2016
  end

  test "updating a date works happily" do

    res = db(:date_night)
      |> filter(id: 1)
      |> update(date: Timex.Date.now)
      |> TestDb.run

    assert res.date.year == 2016
  end


end
