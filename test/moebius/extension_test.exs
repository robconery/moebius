defmodule Moebius.ExtensionTest do
  use ExUnit.Case
  import Moebius.Query
  import TestDb

  test "certain types are ignored on read" do
    res = sql = """
    select to_tsvector('ha ha'),
    now()::timestamptz,
    '127.0.0.1'::inet,
    '6d52474a-912a-4c3c-8ca2-56e55ae2f3f8'::uuid,
    12.00::money,
    12::bigint,
    'hello'::text,
    now()::time,
    now()::date
    """ |> TestDb.run
    IO.inspect res
  end

  # test "dates are able to be inserted" do
  #   res = "insert into date_night(date) values(now()) returning *;" |> TestDb.run
  #   IO.inspect res
  # end

end
