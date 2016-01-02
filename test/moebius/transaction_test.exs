defmodule Moebius.TransactionTest do

  use ExUnit.Case

  import Moebius.Query

  setup do
    "drop table if exists flags" |> run
    db(:logs) |> delete
    db(:users) |> delete
    {:ok, res: true}
  end

  test "transactions with creating a document table" do
    res = Moebius.DocumentQuery.db(:flags)
      |> Moebius.DocumentQuery.save(stars: 50, stripes: 13)

    assert res.id
  end

  test "using a callback without errors" do

    result = transaction fn(pid) ->

      new_user = db(:users)
        |> insert(pid, email: "frodo@test.com")

      db(:logs)
        |> insert(pid, user_id: new_user.id, log: "Hi Frodo")

      new_user
    end

    assert result.email == "frodo@test.com"
  end


  test "using a callback with errors" do

    assert{:error, "insert or update on table \"logs\" violates foreign key constraint \"logs_user_id_fkey\""}
      = transaction fn(pid) ->

      new_user = db(:users)
        |> insert(pid,email: "bilbo@test.com")

      db(:logs)
        |> insert(pid,user_id: 22222, log: "Hi Bilbo")

      new_user
    end

  end


end
