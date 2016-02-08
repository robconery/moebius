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


end
