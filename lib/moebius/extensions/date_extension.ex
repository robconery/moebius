defmodule Moebius.Extensions.DateExtension do
  @behaviour Postgrex.Extension
  import Postgrex.BinaryUtils
  use Postgrex.BinaryExtension, send: "date_send", send: "timestamp_send", send: "timestamptz_send", send: "time_send", send: "timetz_send"

  @gd_epoch :calendar.date_to_gregorian_days({2000, 1, 1})
  @date_max_year 5874897
  @gs_epoch :calendar.datetime_to_gregorian_seconds({{2000, 1, 1}, {0, 0, 0}})
  @timestamp_max_year 294276

  def init(_, _),
    do: nil

  def matching(_), do: [
    type: "timestamptz",
    type: "time",
    type: "date",
  ]

  def format(_),
    do: :text

  def encode(_, %Postgrex.Date{year: year, month: month, day: day}, _, _) when year <= @date_max_year,
    do: <<:calendar.date_to_gregorian_days({year, month, day}) - @gd_epoch :: int32>>

  def encode(_, %Postgrex.Time{hour: hour, min: min, sec: sec, usec: usec}, _, _)
    when hour in 0..23 and min in 0..59 and sec in 0..59 and usec in 0..999_999  do

    time = {hour, min, sec}
    <<:calendar.time_to_seconds(time) * 1_000_000 + usec :: int64>>
  end

  def encode(_, %Postgrex.Timestamp{year: year, month: month, day: day, hour: hour, min: min, sec: sec, usec: usec}, _, _)
  when year <= @timestamp_max_year and hour in 0..23 and min in 0..59 and sec in 0..59 and usec in 0..999_999 do
    datetime = {{year, month, day}, {hour, min, sec}}
    secs = :calendar.datetime_to_gregorian_seconds(datetime) - @gs_epoch
    <<secs * 1_000_000 + usec :: int64>>
  end

  def decode(%Postgrex.TypeInfo{type: data_type},<<microsecs :: int64>>, _, _) when data_type in ["timestamptz", "timestamp"] do
    secs = div(microsecs, 1_000_000)
    usec = rem(microsecs, 1_000_000)
    {{year, month, day}, {hour, min, sec}} = :calendar.gregorian_seconds_to_datetime(secs + @gs_epoch)

    if year < 2000 and usec != 0 do
      sec = sec - 1
      usec = 1_000_000 + usec
    end

    "#{year}-#{month}-#{day} #{hour}:#{min}:#{sec}"
  end

  def decode(%Postgrex.TypeInfo{type: "date"} = info,<<days :: int32>>, _, _) do
    {year, month, day} = :calendar.gregorian_days_to_date(days + @gd_epoch)
    "#{year}-#{month}-#{day}"
  end

  def decode(%Postgrex.TypeInfo{type: "time"}, <<n :: int64>>, _, _),
    do: decode_time(n)

  ## Helpers

  defp decode_time(microsecs) do
    secs = div(microsecs, 1_000_000)
    usec = rem(microsecs, 1_000_000)
    {hour, min, sec} = :calendar.seconds_to_time(secs)
    "#{hour}:#{min}:#{sec}"
  end
end
