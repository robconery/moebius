defmodule Moebius.TransactionTest do
  use ExUnit.Case
  import Moebius.Query
  import TestDb

  setup do
    Moebius.TestData.reset_users!()
    TestDb.run("drop table if exists monkies")
    {:ok, _} = Moebius.DocumentQuery.db(:monkies) |> TestDb.save(%{name: "Setup"})
    :ok
  end

  test "commits and returns the callback's value" do
    result =
      transaction(fn tx ->
        {:ok, new_user} = db(:users) |> insert(email: "frodo@test.com") |> run(tx)
        {:ok, _log} = db(:logs) |> insert(user_id: new_user.id, log: "Hi Frodo") |> run(tx)
        new_user
      end)

    assert %{email: "frodo@test.com", id: id} = result
    assert {:ok, [%{user_id: ^id, log: "Hi Frodo"}]} = db(:logs) |> run()
  end

  test "rolls back everything and returns the error when a statement fails" do
    assert {:error,
            "insert or update on table \"logs\" violates foreign key constraint \"logs_user_id_fkey\""} =
             transaction(fn tx ->
               db(:users) |> insert(email: "bilbo@test.com") |> run(tx)
               db(:logs) |> insert(user_id: 22_222, log: "Hi Bilbo") |> run(tx)
             end)

    assert {:ok, nil} = db(:users) |> filter(email: "bilbo@test.com") |> first()
  end

  test "documents save within a transaction" do
    transaction(fn tx ->
      {:ok, _} = Moebius.DocumentQuery.db(:monkies) |> TestDb.save(%{name: "Mike"}, tx)
      {:ok, _} = Moebius.DocumentQuery.db(:monkies) |> TestDb.save(%{name: "Larry"}, tx)
    end)

    assert {:ok, docs} = Moebius.DocumentQuery.db(:monkies) |> TestDb.run()
    assert docs |> Enum.map(& &1.name) |> Enum.sort() == ["Larry", "Mike", "Setup"]
  end

  test "documents don't save when there's an error within a transaction" do
    assert {:error, "relation \"poopasdasd\" does not exist"} =
             transaction(fn tx ->
               Moebius.DocumentQuery.db(:monkies) |> TestDb.save(%{name: "Mike"}, tx)
               "select * from poopasdasd" |> TestDb.run(tx)
               Moebius.DocumentQuery.db(:monkies) |> TestDb.save(%{name: "Larry"}, tx)
             end)

    assert {:ok, [%{name: "Setup"}]} = Moebius.DocumentQuery.db(:monkies) |> TestDb.run()
  end

  describe "joining and nesting" do
    test "plain run calls in the same process join the transaction" do
      assert {:error, :changed_my_mind} =
               transaction(fn _tx ->
                 {:ok, _} = db(:users) |> insert(email: "joined@test.com") |> run()
                 assert {:ok, %{count: 1}} = db(:users) |> count() |> run()
                 rollback(:changed_my_mind)
               end)

      assert {:ok, %{count: 0}} = db(:users) |> count() |> run()
    end

    test "a raise rolls back and is re-raised" do
      assert_raise ArgumentError, "bad", fn ->
        transaction(fn tx ->
          db(:users) |> insert(email: "raised@test.com") |> run(tx)
          raise ArgumentError, "bad"
        end)
      end

      assert {:ok, nil} = db(:users) |> filter(email: "raised@test.com") |> first()
    end

    test "an inner transaction is a savepoint: it can fail without the outer one" do
      result =
        transaction(fn tx ->
          {:ok, _} = db(:users) |> insert(email: "outer@test.com") |> run(tx)

          inner =
            transaction(fn tx2 ->
              db(:users) |> insert(email: "inner@test.com") |> run(tx2)
              db(:users) |> insert(email: "outer@test.com") |> run(tx2)
            end)

          assert {:error, "duplicate key value violates unique constraint \"users_email_key\""} =
                   inner

          :outer_done
        end)

      assert result == :outer_done
      assert {:ok, [%{email: "outer@test.com"}]} = db(:users) |> run()
    end

    test "an inner transaction that succeeds commits with the outer one" do
      transaction(fn _tx ->
        transaction(fn _tx2 -> db(:users) |> insert(email: "nested@test.com") |> run() end)
      end)

      assert {:ok, %{email: "nested@test.com"}} = db(:users) |> first()
    end

    test "throwing {:error, reason} rolls back and returns it" do
      assert {:error, "nope"} =
               transaction(fn _tx ->
                 db(:users) |> insert(email: "thrown@test.com") |> run()
                 throw({:error, "nope"})
               end)

      assert {:ok, %{count: 0}} = db(:users) |> count() |> run()
    end

    test "the connection is clean after a failed transaction" do
      {:error, _} = transaction(fn tx -> "select * from nope" |> run(tx) end)

      assert {:ok, [%{n: 1}]} = run("select 1 as n")
      assert %{in_use_count: 0} = TestDb.pool_status()
    end
  end
end
