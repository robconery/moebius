defmodule Moebius.Codec.DateTime do
  @moduledoc false
  # An epgsql codec that turns Postgres dates and times into Elixir structs, and back.
  #
  # Postgres sends these as integers: days (date) or microseconds (time, timestamp,
  # timestamptz) counted from 2000-01-01. Reading those directly keeps microsecond
  # precision exactly, with no float seconds on the way.
  #
  # Going in, Erlang tuples (`:calendar.local_time()`, `{y, m, d}`) still work. They are
  # handed to epgsql's own encoder.

  @behaviour :epgsql_codec

  # microseconds between the Unix epoch and the Postgres epoch (2000-01-01)
  @pg_epoch_us 946_684_800_000_000
  @pg_epoch_date ~D[2000-01-01]
  @pg_epoch_naive ~N[2000-01-01 00:00:00.000000]
  @midnight ~T[00:00:00.000000]

  @int64_max 0x7FFFFFFFFFFFFFFF
  @int64_min -0x8000000000000000
  @int32_max 0x7FFFFFFF
  @int32_min -0x80000000

  @impl true
  def init(_opts, _sock), do: []

  @impl true
  def names, do: [:date, :time, :timestamp, :timestamptz]

  @impl true
  def decode(<<@int64_max::signed-64>>, type, _) when type in [:timestamp, :timestamptz],
    do: :infinity

  def decode(<<@int64_min::signed-64>>, type, _) when type in [:timestamp, :timestamptz],
    do: :"-infinity"

  def decode(<<us::signed-64>>, :timestamptz, _),
    do: DateTime.from_unix!(us + @pg_epoch_us, :microsecond)

  def decode(<<us::signed-64>>, :timestamp, _),
    do: NaiveDateTime.add(@pg_epoch_naive, us, :microsecond)

  def decode(<<@int32_max::signed-32>>, :date, _), do: :infinity
  def decode(<<@int32_min::signed-32>>, :date, _), do: :"-infinity"
  def decode(<<days::signed-32>>, :date, _), do: Date.add(@pg_epoch_date, days)

  def decode(<<us::signed-64>>, :time, _), do: Time.add(@midnight, us, :microsecond)

  @impl true
  def encode(%DateTime{} = dt, type, _) when type in [:timestamp, :timestamptz],
    do: <<DateTime.to_unix(dt, :microsecond) - @pg_epoch_us::signed-64>>

  def encode(%NaiveDateTime{} = dt, type, _) when type in [:timestamp, :timestamptz],
    do: <<NaiveDateTime.diff(dt, @pg_epoch_naive, :microsecond)::signed-64>>

  def encode(%Date{} = date, :date, _), do: <<Date.diff(date, @pg_epoch_date)::signed-32>>

  def encode(%Time{} = time, :time, _),
    do: <<Time.diff(time, @midnight, :microsecond)::signed-64>>

  def encode(:infinity, type, _) when type in [:timestamp, :timestamptz],
    do: <<@int64_max::signed-64>>

  def encode(:"-infinity", type, _) when type in [:timestamp, :timestamptz],
    do: <<@int64_min::signed-64>>

  def encode(:infinity, :date, _), do: <<@int32_max::signed-32>>
  def encode(:"-infinity", :date, _), do: <<@int32_min::signed-32>>

  # Erlang tuple formats: {{y,m,d},{h,m,s}}, {y,m,d}, {h,m,s}, {mega, secs, micro}
  def encode(value, type, _) when is_tuple(value), do: :epgsql_idatetime.encode(type, value)

  @impl true
  def decode_text(value, _type, _), do: value
end
