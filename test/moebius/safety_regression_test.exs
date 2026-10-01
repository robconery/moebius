defmodule Moebius.SafetyRegressionTest do
  use ExUnit.Case
  import Moebius.Query
  alias Moebius.DocumentQuery

  defmodule OneDb do
    @moduledoc false
    use Moebius.Database
  end

  setup do
    start_supervised!({OneDb, Moebius.get_connection() ++ [pool_size: 1, checkout_timeout: 100]})
    {:ok, _} = TestDb.run("drop table if exists safety_records")

    {:ok, _} =
      TestDb.run("create table safety_records(id int primary key, tenant_id int, name text)")

    :ok
  end

  test "rejecting parameters releases parse locks before returning the connection" do
    {:ok, [%{pid: backend}]} = OneDb.run("select pg_backend_pid() as pid")

    for params <- [["bad"], []] do
      assert {:error, _} = OneDb.run("select * from safety_records where id = $1", params)
      assert %{in_use_count: 0} = OneDb.pool_status()

      assert {:ok, [%{state: "idle", in_transaction: false}]} =
               TestDb.run(
                 "select state, xact_start is not null as in_transaction from pg_stat_activity where pid = $1",
                 [backend]
               )

      assert {:ok, []} =
               TestDb.run(
                 "select mode from pg_locks where pid = $1 and relation = 'safety_records'::regclass",
                 [backend]
               )
    end

    assert {:ok, [%{pid: ^backend}]} = OneDb.run("select pg_backend_pid() as pid")
  end

  test "a bad parameter rolls back an explicit transaction" do
    assert {:error, "parameter $1 must be int4" <> _} =
             OneDb.transaction(fn tx ->
               OneDb.run("insert into safety_records(id) values (1)", tx)
               OneDb.run("select * from safety_records where id = $1", tx, ["bad"])
             end)

    assert {:ok, %{count: 0}} = db(:safety_records) |> count() |> OneDb.run()
  end

  test "search retains tenant predicates, their parameters and pagination" do
    {:ok, _} =
      TestDb.run("""
      insert into safety_records values
      (1, 10, 'sharedword'), (2, 10, 'sharedword'), (3, 20, 'sharedword')
      """)

    cmd =
      db(:safety_records)
      |> filter(tenant_id: 10)
      |> sort(:id)
      |> offset(1)
      |> limit(1)
      |> search(for: "sharedword", in: [:name])

    assert cmd.params == [10, "sharedword"]
    assert cmd.sql =~ "where (tenant_id = $1) and"
    assert cmd.sql =~ "websearch_to_tsquery($2)"
    assert cmd.sql =~ "order by id asc limit 1 offset 1"
    assert {:ok, [%{id: 2, tenant_id: 10}]} = OneDb.run(cmd)
  end

  test "search groups an existing OR condition and retains joins" do
    {:ok, _} =
      TestDb.run("insert into safety_records values (1, 10, 'different'), (2, 20, 'sharedword')")

    cmd =
      db(:safety_records)
      |> join(:users, on: :safety_records, primary_key: :id, foreign_key: :id)
      |> filter("safety_records.tenant_id = $1 or safety_records.tenant_id = $2", [10, 20])
      |> search(for: "sharedword", in: [:name])

    assert cmd.sql =~ "inner join users"
    assert cmd.sql =~ "where (safety_records.tenant_id = $1 or safety_records.tenant_id = $2) and"
    assert cmd.params == [10, 20, "sharedword"]

    assert {:ok, [%{id: 2}]} =
             db(:safety_records)
             |> filter("tenant_id = $1 or tenant_id = $2", [10, 20])
             |> search(for: "sharedword", in: [:name])
             |> OneDb.run()
  end

  test "document searches retain containment predicates" do
    {:ok, _} = TestDb.run("drop table if exists safety_search_docs")
    cmd = DocumentQuery.db(:safety_search_docs) |> DocumentQuery.searchable([:name])
    {:ok, doc} = OneDb.save(cmd, %{tenant: 10, name: "sharedword"})
    {:ok, _} = OneDb.save(cmd, %{tenant: 20, name: "sharedword"})
    scoped = DocumentQuery.contains(cmd, tenant: 10)

    for search <- [
          DocumentQuery.search(scoped, "sharedword"),
          DocumentQuery.search(scoped, for: "sharedword", in: [:name])
        ] do
      assert search.params == [%{tenant: 10}, "sharedword"]
      assert search.sql =~ "where (body @> $1) and"
      assert {:ok, [%{id: id}]} = OneDb.run(search)
      assert id == doc.id
    end
  end

  test "failed search indexing rolls back the document insert and update" do
    {:ok, _} = TestDb.run("drop table if exists safety_atomic_docs")
    {:ok, _} = OneDb.create_document_table(:safety_atomic_docs)

    {:ok, _} =
      TestDb.run(
        "alter table safety_atomic_docs add constraint reject_search check (search is null)"
      )

    cmd = DocumentQuery.db(:safety_atomic_docs)
    searchable = DocumentQuery.searchable(cmd, [:name])
    assert {:error, message} = OneDb.save(searchable, %{name: "rejected"})
    assert message =~ "reject_search"
    assert {:ok, []} = OneDb.run(cmd)

    {:ok, original} = OneDb.save(cmd, %{name: "original"})
    assert {:error, _} = OneDb.save(searchable, %{original | name: "rejected update"})
    assert {:ok, %{name: "original"}} = OneDb.find(cmd, original.id)
    assert %{in_use_count: 0} = OneDb.pool_status()
  end

  test "searchable saves join an outer transaction and roll back with it" do
    {:ok, _} = TestDb.run("drop table if exists safety_outer_docs")
    {:ok, _} = OneDb.create_document_table(:safety_outer_docs)
    cmd = DocumentQuery.db(:safety_outer_docs) |> DocumentQuery.searchable([:name])

    assert {:error, :undo} =
             OneDb.transaction(fn tx ->
               assert {:ok, _} = OneDb.save(cmd, %{name: "temporary"}, tx)
               OneDb.rollback(:undo)
             end)

    assert {:ok, []} = OneDb.run(cmd)
  end

  test "expired handles are rejected even when the same process borrows the connection again" do
    stale = OneDb.transaction(fn tx -> tx end)
    assert {:error, _} = OneDb.run("select 1", stale)
    assert {:error, _} = OneDb.save(DocumentQuery.db(:safety_unused_docs), %{name: "x"}, stale)

    assert {:error, message} =
             OneDb.transaction(fn _ ->
               OneDb.run("insert into safety_records(id) values (1)", stale)
             end)

    assert message =~ "connection"
    assert {:ok, %{count: 0}} = db(:safety_records) |> count() |> OneDb.run()
  end

  test "a handle cannot be used from another process" do
    assert :done =
             OneDb.transaction(fn tx ->
               task =
                 Task.async(fn -> OneDb.run("insert into safety_records(id) values (1)", tx) end)

               assert {:error, message} = Task.await(task)
               assert message =~ "connection"
               :done
             end)

    assert {:ok, %{count: 0}} = db(:safety_records) |> count() |> OneDb.run()
  end

  test "a handle cannot be used through a different database module" do
    assert :done =
             OneDb.transaction(fn tx ->
               assert {:error, _} = TestDb.run("insert into safety_records(id) values (1)", tx)

               assert {:error, _} =
                        TestDb.save(DocumentQuery.db(:safety_unused_docs), %{name: "x"}, tx)

               :done
             end)

    assert {:ok, %{count: 0}} = db(:safety_records) |> count() |> OneDb.run()
  end

  test "stream callbacks reuse the connection and commit together" do
    cmd = %Moebius.QueryCommand{sql: "select generate_series(1, 3) as id"}

    assert [1, 2, 3] =
             cmd
             |> OneDb.stream(chunk: 1)
             |> Enum.map(fn %{id: id} ->
               assert {:ok, []} = OneDb.run("insert into safety_records(id) values ($1)", [id])
               id
             end)

    assert {:ok, %{count: 3}} = db(:safety_records) |> count() |> OneDb.run()
    assert %{in_use_count: 0} = OneDb.pool_status()
  end

  test "a stream consumer exception rolls back its writes and returns the connection" do
    cmd = %Moebius.QueryCommand{sql: "select generate_series(1, 3) as id"}

    assert_raise RuntimeError, "consumer failed", fn ->
      cmd
      |> OneDb.stream(chunk: 1)
      |> Enum.each(fn %{id: id} ->
        OneDb.run("insert into safety_records(id) values ($1)", [id])
        if id == 2, do: raise("consumer failed")
      end)
    end

    assert {:ok, %{count: 0}} = db(:safety_records) |> count() |> OneDb.run()
    assert %{in_use_count: 0} = OneDb.pool_status()
  end

  test "out-of-range numeric parameters are rejected without replacing the connection" do
    {:ok, [%{pid: backend}]} = OneDb.run("select pg_backend_pid() as pid")

    for number <- [
          Decimal.new(1, 1, 131_072),
          Decimal.new(1, 1, 262_144),
          Decimal.new(1, 1, -65_536)
        ] do
      assert {:error, "parameter $1 must be numeric" <> _} =
               OneDb.run("select $1::numeric as value", [number])
    end

    assert {:ok, [%{pid: ^backend}]} = OneDb.run("select pg_backend_pid() as pid")
  end

  test "numeric range boundaries remain exact" do
    for number <- [Decimal.new(1, 1, 131_071), Decimal.new(1, 1, -16_383)] do
      assert {:ok, [%{value: actual}]} = OneDb.run("select $1::numeric as value", [number])
      assert Decimal.equal?(actual, number)
    end
  end

  test "early stream termination commits successful callback writes and releases the connection" do
    assert [%{id: 1}] =
             %Moebius.QueryCommand{sql: "select generate_series(1, 3) as id"}
             |> OneDb.stream(chunk: 1)
             |> Stream.each(fn %{id: id} ->
               assert {:ok, []} = OneDb.run("insert into safety_records(id) values ($1)", [id])
             end)
             |> Enum.take(1)

    assert {:ok, %{count: 1}} = db(:safety_records) |> count() |> OneDb.run()
    assert %{in_use_count: 0} = OneDb.pool_status()
  end

  test "a stream database error rolls back callback writes" do
    assert_raise Moebius.Error, ~r/duplicate key/, fn ->
      %Moebius.QueryCommand{sql: "select generate_series(1, 3) as id"}
      |> OneDb.stream(chunk: 1)
      |> Enum.each(fn _ -> OneDb.run("insert into safety_records(id) values (1)") end)
    end

    assert {:ok, %{count: 0}} = db(:safety_records) |> count() |> OneDb.run()
    assert %{in_use_count: 0} = OneDb.pool_status()
  end

  test "a suspended stream cannot outlive its enclosing transaction" do
    {:suspended, _, continuation} =
      OneDb.transaction(fn _ ->
        stream =
          %Moebius.QueryCommand{sql: "select generate_series(1, 3) as id"} |> OneDb.stream()

        Enumerable.reduce(stream, {:cont, []}, fn row, acc -> {:suspend, [row | acc]} end)
      end)

    assert_raise Moebius.Error, ~r/active checkout/, fn -> continuation.({:cont, []}) end
    assert {:ok, [%{n: 1}]} = OneDb.run("select 1 as n")
    assert %{in_use_count: 0} = OneDb.pool_status()
  end

  test "server timeouts are enabled by default" do
    assert {:ok, [%{statement_timeout: "30s"}]} = OneDb.run("show statement_timeout")
    assert {:ok, [%{lock_timeout: "5s"}]} = OneDb.run("show lock_timeout")

    assert {:ok, [%{idle_in_transaction_session_timeout: "30s"}]} =
             OneDb.run("show idle_in_transaction_session_timeout")
  end
end
