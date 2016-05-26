defmodule Moebius.TransactionTest do

  use ExUnit.Case

  import Moebius.Query
  import TestDb

  setup do
    "drop table if exists flags" |> run
    db(:logs) |> delete |> run
    db(:users) |> delete |> run
    {:ok, res: true}
  end

  test "using a callback without errors" do

    result = transaction fn(tx) ->

      new_user = db(:users)
        |> insert(email: "frodo@test.com")
        |> run(tx)

      db(:logs)
        |> insert(user_id: new_user.id, log: "Hi Frodo")
        |> run(tx)

      new_user
    end

    assert result.email == "frodo@test.com"
  end


  test "using a callback with errors" do

    assert{:error, "insert or update on table \"logs\" violates foreign key constraint \"logs_user_id_fkey\""}
      = transaction fn(tx) ->

      new_user = db(:users)
        |> insert(email: "bilbo@test.com")
        |> run(tx)

      db(:logs)
        |> insert(user_id: 22222, log: "Hi Bilbo")
        |> run(tx)

      new_user
    end

  end

  test "documents save within a transaction" do
    "drop table if exists monkies;" |> TestDb.run
    res = transaction fn(tx) ->
      Moebius.DocumentQuery.db(:monkies) |> Moebius.DocumentQuery.searchable([:name]) |> TestDb.save(%{name: "Mike"}, tx)
      Moebius.DocumentQuery.db(:monkies) |> Moebius.DocumentQuery.searchable([:name]) |> TestDb.save(%{name: "Larry"}, tx)
    end
    case res do
      {:error, err} -> flunk "Saving a document with searchable failed. #{inspect err}"
      res -> assert res
    end
  end

  test "documents don't save when there's an error within a transaction" do
    res = transaction fn(tx) ->
      Moebius.DocumentQuery.db(:monkies) |> TestDb.save(%{name: "Mike"}, tx)
      "select * from poopasdasd" |> TestDb.run(tx)
      Moebius.DocumentQuery.db(:monkies) |> TestDb.save(%{name: "Larry"}, tx)
    end
    case res do
      {:error, message} -> assert message
      true -> flunk "Nope, a result came back"
    end
  end

end
