defmodule Moebius.TransactionTest do

  use ExUnit.Case
  import Moebius.Query

  def insert_user(tx) do
    db(:users)
      |> insert(email: "tx@test.com", first: "Rob", last: "Blob")
      |> tx.queue
  end

  defp insert_log(tx, new_user) do
    db(:logs)
      |> insert(user_id: new_user.id, entry: "This is an entry")
      |> tx.queue
  end

  test "queuing a transaction" do
    cmds = Moebius.transaction fn(conn) ->
      {:ok, new_user} = db(:users)
        |> insert(email: "tx@test.com", first: "Rob", last: "Blob")
        |> execute(conn)

      {:ok, log} = db(:logs)
        |> insert(user_id: new_user.id, log: "This is an entry")
        |> execute(conn)
      new_user
    end
    IO.inspect cmds
  end

end
