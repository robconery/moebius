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
end
