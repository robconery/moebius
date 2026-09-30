defmodule Moebius.SecurityTest do
  use ExUnit.Case
  import Moebius.Query

  doctest Moebius.Identifier

  setup do
    Moebius.TestData.reset_users!()
    {:ok, user} = db(:users) |> insert(email: "victim@test.com") |> TestDb.run()
    {:ok, user: user}
  end

  describe "values are always parameters" do
    test "find/2 sends the id as a parameter", %{user: user} do
      assert {:error, "parameter $1 must be int4" <> _} =
               db(:users) |> TestDb.find("#{user.id} or 1=1")

      assert {:ok, %{email: "victim@test.com"}} = db(:users) |> TestDb.find("#{user.id}")
    end

    test "document find/2 and delete/2 use parameters" do
      TestDb.run("drop table if exists safe_docs")
      {:ok, doc} = Moebius.DocumentQuery.db(:safe_docs) |> TestDb.save(%{name: "keep me"})

      assert %{sql: sql, params: [id]} =
               Moebius.DocumentQuery.db(:safe_docs) |> Moebius.DocumentQuery.find(doc.id)

      assert sql =~ "where id = $1"
      assert id == doc.id

      assert {:error, _} =
               Moebius.DocumentQuery.db(:safe_docs)
               |> Moebius.DocumentQuery.delete("1 or 1=1")
               |> TestDb.run()

      assert {:ok, [%{name: "keep me"}]} = Moebius.DocumentQuery.db(:safe_docs) |> TestDb.run()
    end

    test "contains/2 sends the document as a parameter, so quotes are just data" do
      TestDb.run("drop table if exists safe_docs")
      {:ok, _} = Moebius.DocumentQuery.db(:safe_docs) |> TestDb.save(%{name: "O'Brien"})

      cmd =
        Moebius.DocumentQuery.db(:safe_docs) |> Moebius.DocumentQuery.contains(name: "O'Brien")

      assert cmd.where == " where body @> $1"

      assert {:ok, %{name: "O'Brien"}} = TestDb.first(cmd)

      assert {:ok, nil} =
               Moebius.DocumentQuery.db(:safe_docs)
               |> Moebius.DocumentQuery.contains(name: "x'}' or '1'='1")
               |> TestDb.first()
    end
  end

  describe "names are checked" do
    test "a table name that isn't a name raises" do
      assert_raise ArgumentError, ~r/invalid SQL identifier/, fn ->
        db("users; drop table users")
      end

      assert_raise ArgumentError, fn -> Moebius.DocumentQuery.db("docs--") end
    end

    test "schema-qualified and quoted names are fine" do
      assert db("public.users") |> select() |> Map.get(:sql) == "select * from public.users;"

      assert db(~s("Order Items")) |> select() |> Map.get(:sql) ==
               ~s(select * from "Order Items";)
    end

    test "column names from keywords are checked" do
      assert_raise ArgumentError, fn -> db(:users) |> filter([{:"id = 1 or 1", 1}]) end

      assert_raise ArgumentError, fn ->
        db(:users) |> insert([{:"email) values ('x'); --", "y"}])
      end

      assert_raise ArgumentError, fn ->
        db(:users) |> filter(email: "x") |> update([{:"email = 'x' --", 1}])
      end
    end

    test "sort directions are checked" do
      assert_raise ArgumentError, ~r/sort direction/, fn ->
        db(:users) |> sort(:id, "desc; drop table users")
      end

      assert db(:users) |> sort(:id, "DESC") |> Map.get(:order) == " order by id desc"
    end

    test "document field names are quoted, so any key is safe" do
      cmd =
        Moebius.DocumentQuery.db(:docs) |> Moebius.DocumentQuery.filter(:"x' = 'x' or 'a", ">", 1)

      assert cmd.where == " where body -> 'x'' = ''x'' or ''a' > $1"
    end

    test "document field names can't contain a backslash" do
      assert_raise ArgumentError, ~r/backslash/, fn ->
        Moebius.DocumentQuery.db(:docs)
        |> Moebius.DocumentQuery.sort(:"x\\'; drop table users; --")
      end
    end

    test "stream chunk sizes must be positive integers" do
      assert_raise ArgumentError, ~r/:chunk/, fn ->
        db(:users) |> TestDb.stream(chunk: "1; drop")
      end

      assert_raise ArgumentError, ~r/:chunk/, fn -> db(:users) |> TestDb.stream(chunk: 0) end
    end

    test "document operators are checked" do
      assert_raise ArgumentError, ~r/unsupported document operator/, fn ->
        Moebius.DocumentQuery.db(:docs) |> Moebius.DocumentQuery.filter(:a, "= 1 or 1 =", 1)
      end
    end

    test "limit and offset must be integers" do
      # the type checker rejects a literal string here at compile time; this is the runtime check
      hostile = Enum.random(["1; drop table users"])
      assert_raise FunctionClauseError, fn -> db(:users) |> offset(hostile) end
      assert_raise FunctionClauseError, fn -> db(:users) |> limit(-1) end
    end

    test "join types and keys are checked" do
      assert_raise ArgumentError, fn ->
        db(:users) |> join(:logs, join: "left; drop table users")
      end

      assert_raise ArgumentError, fn ->
        db(:users) |> join(:logs, foreign_key: "user_id = 1 or 1")
      end
    end

    test "SQL file names can't leave the scripts folder" do
      assert_raise ArgumentError, ~r/invalid SQL file name/, fn ->
        sql_file_command(:"../config/config")
      end

      assert_raise ArgumentError, fn -> sql_file_command("/etc/passwd") end
    end

    test "function names are checked" do
      assert_raise ArgumentError, fn ->
        function_command(:"now(); drop table users; select now")
      end
    end
  end

  test "the users table survived all of that", %{user: user} do
    assert {:ok, %{id: id}} = db(:users) |> TestDb.find(user.id)
    assert id == user.id
  end
end
