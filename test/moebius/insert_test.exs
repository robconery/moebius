defmodule Moebius.InsertTest do
  use ExUnit.Case
  import Moebius.Query

  setup do
    Moebius.TestData.reset_users!()
    :ok
  end

  test "builds an insert with a placeholder per column" do
    cmd = db(:users) |> insert(email: "test@test.com", first: "Test", last: "User")

    assert cmd.sql == "insert into users(email, first, last) values($1, $2, $3) returning *;"
    assert cmd.params == ["test@test.com", "Test", "User"]
    assert cmd.type == :insert
  end

  test "an empty insert raises instead of building invalid SQL" do
    assert_raise ArgumentError, ~r/at least one column/, fn -> db(:users) |> insert([]) end
  end

  test "returns the inserted row, defaults included" do
    assert {:ok,
            %{
              email: "test@test.com",
              first: "Test",
              last: "User",
              id: id,
              order_count: 10,
              profile: nil,
              roles: nil
            }} =
             db(:users)
             |> insert(email: "test@test.com", first: "Test", last: "User")
             |> TestDb.run()

    assert is_integer(id)
  end

  test "returns an error on a constraint violation" do
    {:ok, _} = db(:users) |> insert(email: "dupe@test.com") |> TestDb.run()

    assert {:error, "duplicate key value violates unique constraint \"users_email_key\""} =
             db(:users) |> insert(email: "dupe@test.com") |> TestDb.run()
  end

  test "json and array columns round-trip" do
    assert {:ok, %{profile: %{"theme" => "dark"}, roles: ["admin", "dev"]}} =
             db(:users)
             |> insert(email: "json@test.com", profile: %{theme: "dark"}, roles: ["admin", "dev"])
             |> TestDb.run()
  end

  describe "ignore_conflict" do
    test "adds on conflict do nothing before returning" do
      cmd = db(:users) |> insert(email: "a@test.com") |> ignore_conflict()

      assert cmd.sql ==
               "insert into users(email) values($1) on conflict do nothing returning *;"
    end

    test "names the conflict target columns" do
      assert db(:users) |> insert(email: "a@test.com") |> ignore_conflict(:email) |> Map.get(:sql) ==
               "insert into users(email) values($1) on conflict (email) do nothing returning *;"

      assert db(:users)
             |> insert(email: "a@test.com", first: "A")
             |> ignore_conflict([:email, :first])
             |> Map.get(:sql) ==
               "insert into users(email, first) values($1, $2) on conflict (email, first) do nothing returning *;"
    end

    test "applies to every command in a bulk insert" do
      %Moebius.CommandBatch{commands: [cmd]} =
        db(:users) |> bulk_insert([[email: "a@test.com"]]) |> ignore_conflict(:email)

      assert cmd.sql == "insert into users(email) values ($1) on conflict (email) do nothing;"
    end

    test "rejects an unsafe column name" do
      assert_raise ArgumentError, fn ->
        db(:users)
        |> insert(email: "a@test.com")
        |> ignore_conflict("email); drop table users;--")
      end
    end

    test "raises when not piped after an insert" do
      assert_raise ArgumentError, ~r/must follow insert/, fn ->
        db(:users) |> filter(id: 1) |> update(first: "X") |> ignore_conflict()
      end
    end

    test "skips a duplicate and returns nil" do
      {:ok, %{id: id}} = db(:users) |> insert(email: "dupe@test.com") |> TestDb.run()

      assert {:ok, nil} =
               db(:users)
               |> insert(email: "dupe@test.com")
               |> ignore_conflict(:email)
               |> TestDb.run()

      assert {:ok, [%{id: ^id}]} = db(:users) |> filter(email: "dupe@test.com") |> TestDb.run()
    end

    test "still returns an error for a different constraint" do
      assert {:error, _} =
               db(:users) |> insert(first: "No email") |> ignore_conflict(:email) |> TestDb.run()
    end

    test "bulk insert skips existing rows and inserts the rest" do
      {:ok, _} = db(:users) |> insert(email: "dupe@test.com") |> TestDb.run()

      assert [ok: %Moebius.Result{num_rows: 1}] =
               db(:users)
               |> bulk_insert([[email: "dupe@test.com"], [email: "new@test.com"]])
               |> ignore_conflict(:email)
               |> TestDb.transact_batch()

      assert {:ok, [_, _]} =
               db(:users)
               |> filter("email in ('dupe@test.com', 'new@test.com')")
               |> TestDb.run()
    end
  end
end
