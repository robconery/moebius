defmodule Moebius.TransactionTest do

  use ExUnit.Case

  import Moebius.Query

  setup do
    db(:logs) |> delete
    db(:users) |> delete
    {:ok, res: true}
  end

  test "using a callback without errors" do

    result = transaction fn(pid) ->

      new_user = with(:users)
        |> insert(pid, email: "frodo@test.com")

      with(:logs)
        |> insert(pid, user_id: new_user.id, log: "Hi Frodo")

      new_user
    end

    assert result.email == "frodo@test.com"
  end


  test "using a callback with errors" do

    assert{:error, "insert or update on table \"logs\" violates foreign key constraint \"logs_user_id_fkey\""}
      = transaction fn(pid) ->

      new_user = with(:users)
        |> insert(pid,email: "bilbo@test.com")

      with(:logs)
        |> insert(pid,user_id: 22222, log: "Hi Bilbo")

      new_user
    end

  end
  

end
