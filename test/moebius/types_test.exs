defmodule Moebius.TypesTest do
  use ExUnit.Case

  # Each value goes in as a parameter and comes back as a result, so both directions of
  # every codec are covered.
  defp round_trip(value, type) do
    {:ok, [%{v: v}]} = TestDb.run("select $1::#{type} as v", [value])
    v
  end

  defp select(sql) do
    {:ok, [%{v: v}]} = TestDb.run("select #{sql} as v")
    v
  end

  describe "numeric" do
    test "comes back as Decimal with the column's scale" do
      assert select("12.50::numeric(10,2)") == Decimal.new("12.50")
      assert select("0::numeric(10,2)") == Decimal.new("0.00")
      assert select("-0.001::numeric") == Decimal.new("-0.001")
      assert select("20000::numeric") == Decimal.new("20000")
    end

    test "keeps full precision, past Decimal's 34-digit parsing limit" do
      big = "12345678901234567890.123456789012345678901234567890"
      assert select("'#{big}'::numeric") == Decimal.new(big, max_digits: :infinity)
    end

    test "numeric strings past 34 digits are refused as parameters" do
      assert {:error, "parameter $1 must be numeric" <> _} =
               TestDb.run("select $1::numeric as v", [String.duplicate("9", 40)])
    end

    test "round-trips Decimals, integers, floats and numeric strings" do
      for value <- [
            "0",
            "1",
            "-1",
            "12.50",
            "0.0001",
            "10000",
            "99999999.99990000",
            "-123456789.987654321"
          ] do
        assert Decimal.equal?(round_trip(Decimal.new(value), "numeric"), Decimal.new(value)),
               "round trip failed for #{value}"
      end

      assert round_trip(42, "numeric") == Decimal.new("42")
      assert round_trip(1.5, "numeric") == Decimal.new("1.5")
      assert round_trip("3.14159", "numeric") == Decimal.new("3.14159")
    end

    test "NaN and infinities" do
      assert Decimal.nan?(select("'NaN'::numeric"))
      assert round_trip(Decimal.new("Infinity"), "numeric") == Decimal.new("Infinity")
      assert round_trip(Decimal.new("-Infinity"), "numeric") == Decimal.new("-Infinity")
    end

    test "sums and averages are Decimals" do
      assert {:ok, [%{avg: avg}]} = TestDb.run("select avg(x) from (values (1), (2)) t(x)")
      assert avg == Decimal.new("1.5000000000000000")
    end
  end

  describe "dates and times" do
    test "timestamptz is a UTC DateTime with microseconds" do
      assert select("'2026-09-30 10:11:12.345678+02'::timestamptz") ==
               ~U[2026-09-30 08:11:12.345678Z]
    end

    test "timestamp is a NaiveDateTime with microseconds" do
      assert select("'2026-09-30 10:11:12.5'::timestamp") == ~N[2026-09-30 10:11:12.500000]
    end

    test "date and time" do
      assert select("'1999-12-31'::date") == ~D[1999-12-31]
      assert select("'23:59:59.999999'::time") == ~T[23:59:59.999999]
    end

    test "Elixir structs round-trip as parameters" do
      assert round_trip(~U[2026-01-02 03:04:05.123456Z], "timestamptz") ==
               ~U[2026-01-02 03:04:05.123456Z]

      assert round_trip(~N[1970-01-01 00:00:00.000001], "timestamp") ==
               ~N[1970-01-01 00:00:00.000001]

      assert round_trip(~D[2000-01-01], "date") == ~D[2000-01-01]
      assert round_trip(~D[1492-10-12], "date") == ~D[1492-10-12]
      assert round_trip(~T[12:00:00.000000], "time") == ~T[12:00:00.000000]
    end

    test "a DateTime in another zone is stored as the same instant" do
      # 14:00 in Paris in June is 12:00 UTC
      paris = %DateTime{
        year: 2026,
        month: 6,
        day: 1,
        hour: 14,
        minute: 0,
        second: 0,
        microsecond: {0, 6},
        time_zone: "Europe/Paris",
        zone_abbr: "CEST",
        utc_offset: 3600,
        std_offset: 3600
      }

      assert round_trip(paris, "timestamptz") == ~U[2026-06-01 12:00:00.000000Z]
    end

    test "Erlang tuples still work as parameters" do
      assert round_trip({{2026, 1, 2}, {3, 4, 5}}, "timestamp") == ~N[2026-01-02 03:04:05.000000]
      assert round_trip({2026, 1, 2}, "date") == ~D[2026-01-02]
    end

    test "infinity" do
      assert select("'infinity'::timestamptz") == :infinity
      assert select("'-infinity'::date") == :"-infinity"
      assert round_trip(:infinity, "timestamp") == :infinity
    end

    test "arrays of dates" do
      assert round_trip([~D[2026-01-01], nil, ~D[2026-12-31]], "date[]") ==
               [~D[2026-01-01], nil, ~D[2026-12-31]]
    end
  end

  describe "everything else" do
    test "NULL is nil, both ways" do
      assert select("null::text") == nil
      assert round_trip(nil, "int4") == nil
    end

    test "json and jsonb decode to string-keyed maps" do
      assert select(~s('{"a": [1, 2.5, true, null]}'::jsonb)) == %{"a" => [1, 2.5, true, nil]}
      assert round_trip(%{b: %{c: "d"}}, "json") == %{"b" => %{"c" => "d"}}
      assert round_trip("just a string", "jsonb") == "just a string"
    end

    test "uuid is a string" do
      uuid = "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11"
      assert round_trip(uuid, "uuid") == uuid
      assert round_trip("A0EEBC999C0B4EF8BB6D6BB9BD380A11", "uuid") == uuid
    end

    test "a string that isn't a uuid is an error, not a connection crash" do
      assert {:error, "parameter $1 must be uuid, got: \"not-a-uuid\""} =
               TestDb.run("select $1::uuid as v", ["not-a-uuid"])

      assert {:ok, [%{v: 1}]} = TestDb.run("select 1 as v")
    end

    test "booleans, integers, floats, text and arrays" do
      assert round_trip(true, "bool") == true
      assert round_trip(9_223_372_036_854_775_807, "int8") == 9_223_372_036_854_775_807
      assert round_trip(1.25, "float8") == 1.25
      assert round_trip("héllo 👋", "text") == "héllo 👋"
      assert round_trip([[1, 2], [3, 4]], "int4[]") == [[1, 2], [3, 4]]
    end

    test "tsvector comes back as text instead of raising" do
      assert select("to_tsvector('english', 'the quick brown fox')") ==
               "'brown':3 'fox':4 'quick':2"
    end
  end
end
