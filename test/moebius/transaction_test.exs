defmodule Moebius.TransactionTest do

  use ExUnit.Case
  import Moebius.Query

  test "queuing a transaction" do
    cmds = Moebius.transaction fn(conn) ->
      new_user = :users
        |> db()
        |> insert(email: "tx@test.com", first: "Rob", last: "Blob")
        |> execute(conn)

      :logs
        |> db()
        |> insert(user_id: new_user.id, log: "This is an entry")
        |> execute(conn)
      new_user
    end

    IO.inspect cmds

    assert cmds
  end
end
