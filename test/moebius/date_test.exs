defmodule Moebius.DateTests do
  use ExUnit.Case
  import Moebius.Query

  setup_all do
    res = "select * from date_night" |> TestDb.run
    {:ok, data: res}
  end

  test "Timex will parse a date without fucking itself" do
    ds = "2016-3-2 0:25:11"
    case Timex.parse(ds, "{YYYY}-{_M}-{_D} {_h24}:{_m}:{_s}") do
      {:ok, date} -> assert date.year == 2016
      {:error, err} -> flunk err
    end
  end

  test "Dates are transformed to Times", %{data: [ %{id: _id, date: date} | _rest]} do
    assert is_binary(date)
  end

  test "adding a date works happily with Timex" do
    res = db(:date_night)
      |> insert(date: Timex.DateTime.now)
      |> TestDb.run

    assert is_binary(res.date)
  end

  test "adding a date works happily with Timex via SQL file" do
    res = sql_file(:date, [Timex.DateTime.now])
      |> TestDb.run
      |> List.first

    assert is_binary(res.date)
  end

  test "returning dates come back as strings" do
    res = db(:date_night)
      |> TestDb.first
    assert is_binary(res.date)
  end

  test "updating a date works happily with :calendar" do

    res = db(:date_night)
      |> filter(id: 1)
      |> update(date: :calendar.local_time)
      |> TestDb.run

    assert is_binary(res.date)
  end

  test "string to date transformer returns Timex date" do
    res = "2016-2-26 17:39:34" |> Moebius.Transformer.check_for_string_date
    refute is_binary(res)
  end

  test "updating a date works with timestamp string" do
    res = db(:date_night)
      |> filter(id: 1)
      |> update(date: "2016-2-26 17:39:34")
      |> TestDb.run

    assert res.id
  end

  test "updating a date works with single second stamps" do
    res = db(:date_night)
      |> filter(id: 1)
      |> update(date: "2016-2-25 19:48:9")
      |> TestDb.run

    assert res.id
  end

  test "updating a date works with roundtrip date", %{data: [ %{id: _id, date: date} | _rest]} do
    res = db(:date_night)
      |> filter(id: 1)
      |> update(date: date)
      |> TestDb.run

    assert res.id
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

  test "filter by date range using binaries" do
    %{min_date: start_at, max_date: end_at} = date_range

    res = db(:date_night)
    |> filter("date BETWEEN $1 AND $2", [start_at, end_at])
    |> TestDb.run

    assert is_list(res)
    refute [] == res
  end

  test "filter by date range using atoms" do
    res = db(:date_night)
    |> filter("date BETWEEN $1 AND $2", [:yesterday, :tomorrow])
    |> TestDb.run

    assert is_list(res)
    refute [] == res
  end

  test "filter by a single date" do
    db(:date_night)
    |> filter(id: 1)
    |> update(date: :tomorrow)
    |> TestDb.run

    res = db(:date_night)
    |> filter(date: :tomorrow)
    |> TestDb.run

    assert is_list(res)
    refute [] == res
  end

  defp date_range do
    %Moebius.QueryCommand{sql: "select min(date) as min_date, max(date) as max_date from date_night;"}
    |> TestDb.first
  end
end
