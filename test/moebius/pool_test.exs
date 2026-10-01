defmodule Moebius.PoolTest do
  use ExUnit.Case
  import ExUnit.CaptureLog
  import Moebius.Query

  # A second database module with its own small pool, so these tests can exhaust it,
  # time it out and break it without touching TestDb.
  defmodule TinyDb do
    @moduledoc false
    use Moebius.Database
  end

  defmodule SlowDb do
    @moduledoc false
    use Moebius.Database
  end

  defmodule NeverStarted do
    @moduledoc false
    use Moebius.Database
  end

  setup do
    base = Moebius.get_connection()
    start_supervised!({TinyDb, base ++ [pool_size: 1, pool_min: 1, checkout_timeout: 100]})
    start_supervised!({SlowDb, base ++ [pool_size: 1, pool_min: 1, statement_timeout: "100ms"]})
    :ok
  end

  describe "parameters" do
    test "a parameter of the wrong type is an error, and the connection survives" do
      assert {:error, "parameter $1 must be int4, got: \"five\""} =
               TinyDb.run("select $1::int as n", ["five"])

      assert {:ok, [%{n: 5}]} = TinyDb.run("select $1::int as n", [5])
    end

    test "the wrong number of parameters is an error" do
      assert {:error, "the statement expects 2 parameters but got 1"} =
               TinyDb.run("select $1::int + $2::int as n", [1])
    end

    test "a value JSON can't encode is an error, not a crash" do
      assert {:error, "parameter $1 must be jsonb" <> _} =
               TinyDb.run("select $1::jsonb as j", [%{pid: self()}])

      assert {:ok, [%{j: %{"ok" => true}}]} = TinyDb.run("select $1::jsonb as j", [%{ok: true}])
    end

    test "array elements are checked too" do
      assert {:error, "parameter $1 must be int4[], got: [1, \"2\"]"} =
               TinyDb.run("select $1::int[] as a", [[1, "2"]])
    end

    test "a number the type can't hold is an error, and the connection survives" do
      backend = backend_pid()

      assert {:error, "parameter $1 must be int2, got: 32768"} =
               TinyDb.run("select $1::int2 as n", [32_768])

      assert {:error, "parameter $1 must be int4, got: -2147483649"} =
               TinyDb.run("select $1::int4 as n", [-2_147_483_649])

      assert {:error, "parameter $1 must be int8, got: 9223372036854775808"} =
               TinyDb.run("select $1::int8 as n", [9_223_372_036_854_775_808])

      assert {:error, "parameter $1 must be int4[], got: [1, 2147483648]"} =
               TinyDb.run("select $1::int4[] as a", [[1, 2_147_483_648]])

      assert {:error, "parameter $1 must be float8, got: 1000" <> _} =
               TinyDb.run("select $1::float8 as n", [Integer.pow(10, 400)])

      assert {:ok, [%{n: -32_768}]} = TinyDb.run("select $1::int2 as n", [-32_768])
      assert {:ok, [%{n: 3.0}]} = TinyDb.run("select $1::float8 as n", [3])
      assert backend_pid() == backend
    end

    test "find/2 with an id too big for the key is an error, as from a URL" do
      backend = backend_pid()

      assert {:error, "parameter $1 must be int4, got: 99999999999"} =
               db(:users) |> TinyDb.find("99999999999")

      assert backend_pid() == backend
    end
  end

  describe "a transaction opened by hand" do
    test "begin through run/1 is refused, and the connection goes back clean" do
      assert {:error, "a transaction can't be opened with run" <> _} = TinyDb.run("begin")

      assert {:error, "a transaction can't be opened with run" <> _} =
               TinyDb.run("start transaction")

      # each statement is its own transaction again, so each gets a new transaction id
      {:ok, [%{id: first}]} = TinyDb.run("select txid_current() as id")
      {:ok, [%{id: second}]} = TinyDb.run("select txid_current() as id")
      assert second != first
    end

    test "inside transaction/1 a begin is left alone" do
      assert {:ok, [%{n: 1}]} =
               TinyDb.transaction(fn _tx ->
                 {:ok, []} = TinyDb.run("begin")
                 TinyDb.run("select 1 as n")
               end)
    end
  end

  describe "the pool" do
    test "reports its size and use" do
      assert %{max_count: 1, in_use_count: 0} = TinyDb.pool_status()
    end

    test "a busy pool times out with an error instead of hanging" do
      test = self()

      holder =
        spawn(fn ->
          TinyDb.transaction(fn _tx ->
            send(test, :holding)
            receive do: (:release -> :ok)
          end)
        end)

      assert_receive :holding

      assert {:error, "no connection available from Moebius.PoolTest.TinyDb within 100ms"} =
               TinyDb.run("select 1")

      send(holder, :release)
      assert {:ok, [%{n: 1}]} = retry(fn -> TinyDb.run("select 1 as n") end)
    end

    test "the connection goes back after a raise" do
      assert_raise RuntimeError, fn ->
        TinyDb.transaction(fn _tx -> raise "boom" end)
      end

      assert %{in_use_count: 0} = TinyDb.pool_status()
      assert {:ok, [%{n: 1}]} = TinyDb.run("select 1 as n")
    end

    test "a connection that dies mid-transaction is replaced" do
      # pooler logs the dead member asynchronously; capture_log only keeps the run quiet
      capture_log(fn ->
        assert {:error, "connection lost" <> _} =
                 TinyDb.transaction(fn tx ->
                   Process.exit(tx.pid, :kill)
                   TinyDb.run("select 1", tx)
                 end)
      end)

      assert {:ok, [%{n: 1}]} = retry(fn -> TinyDb.run("select 1 as n") end)
    end

    test "a database module that isn't started says so" do
      assert {:error, "Moebius.PoolTest.NeverStarted isn't started"} =
               NeverStarted.run("select 1")
    end
  end

  describe "statement_timeout" do
    test "a slow query is cancelled by the server" do
      assert {:error, "canceling statement due to statement timeout"} =
               SlowDb.run("select pg_sleep(2)")

      assert {:ok, [%{n: 1}]} = SlowDb.run("select 1 as n")
    end
  end

  describe "starting" do
    defmodule WrappedDb do
      @moduledoc false
      use Moebius.Database
    end

    test "options can be wrapped in a list, as in {Db, [opts]}" do
      start_supervised!({WrappedDb, [Moebius.get_connection() ++ [pool_size: 2]]})

      assert {:ok, [%{n: 1}]} = WrappedDb.run("select 1 as n")
      assert %{max_count: 2} = WrappedDb.pool_status()
    end

    test "a url is parsed" do
      start_supervised!(
        {WrappedDb, url: "postgres://postgres:postgres@localhost:5432/moebius_test"}
      )

      assert {:ok, [%{db: "moebius_test"}]} = WrappedDb.run("select current_database() as db")
    end

    test "a pool whose database is down still starts, and calls return errors" do
      log =
        capture_log(fn ->
          opts = Moebius.get_connection() |> Keyword.merge(port: 1, checkout_timeout: 50)
          start_supervised!({WrappedDb, opts})

          assert {:error, _} = WrappedDb.run("select 1")
        end)

      assert log =~ "econnrefused"
    end
  end

  describe "two databases" do
    test "each module runs on its own pool" do
      Moebius.TestData.reset_users!()
      {:ok, _} = db(:users) |> insert(email: "shared@test.com") |> TinyDb.run()

      assert {:ok, %{email: "shared@test.com"}} = db(:users) |> TestDb.first()
      assert %{max_count: 1} = TinyDb.pool_status()
      assert %{max_count: 10} = TestDb.pool_status()
    end
  end

  # TinyDb has one connection, so a different backend means that connection was replaced
  defp backend_pid do
    {:ok, [%{pid: pid}]} = TinyDb.run("select pg_backend_pid() as pid")
    pid
  end

  # pooler replaces members asynchronously; give it a moment
  defp retry(fun, attempts \\ 50) do
    case fun.() do
      {:error, _} when attempts > 0 ->
        Process.sleep(10)
        retry(fun, attempts - 1)

      result ->
        result
    end
  end
end
