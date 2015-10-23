defmodule Moebius.TransactionTest do

  use ExUnit.Case

  import Moebius.Query

  setup do
    db(:logs) |> delete
    db(:users) |> delete
    {:ok, res: true}
  end

  test "using a callback without errors" do

    result = transaction fn(cmd) ->

      new_user = with(cmd, :users)
        |> insert(email: "frodo@test.com")
        |> execute

      with(cmd, :logs)
        |> insert(user_id: new_user.id, log: "Hi Frodo")
        |> execute

      new_user
    end

    assert result.email == "frodo@test.com"
  end


  test "using a callback with errors" do

    assert{:error, "insert or update on table \"logs\" violates foreign key constraint \"logs_user_id_fkey\""}
      = transaction fn(tx) ->

      new_user = with(tx, :users)
        |> insert(email: "bilbo@test.com")
        |> execute

      with(tx, :logs)
        |> insert(user_id: 22222, log: "Hi Bilbo")
        |> execute

      new_user
    end

  end
  #
  # test "queuing a transaction and passing data back" do
  #
  #   res = begin
  #     |> create_user("jenniferOjenny@test.com")
  #     |> log_it
  #     |> commit
  #
  #   assert res
  # end
  #
  # test "queuing a transaction and passing data back, nicely" do
  #
  #   ideally
  #     |> create_user("bibble@test.com")
  #     |> log_it
  #     |> win
  #
  # end
  #
  # test "queuing a transaction that fails will throw" do
  #
  #   assert catch_error (
  #     ideally
  #       |> create_user("bucky@test.com")
  #       |> log_it_poorly
  #       |> win
  #   ) == "insert or update on table \"logs\" violates foreign key constraint \"logs_user_id_fkey\""
  # end
  #
  #
  # defp create_user(cmd, email) do
  #
  #   new_user =
  #
  #     db(cmd, :users)
  #       |> insert(email: email, first: "Rob", last: "Blob")
  #       |> execute
  #
  #   %{cmd: cmd, new_user: new_user}
  #
  # end
  #
  # defp log_it(args) do
  #
  #   res = db(args.cmd,:logs)
  #     |> insert(user_id: args.new_user.id, log: "New user addd")
  #     |> execute
  #
  #   args.cmd
  #
  # end
  #
  # defp log_it_poorly(args) do
  #
  #   res = db(args.cmd,:logs)
  #     |> insert(user_id: 0, log: "New user addd")
  #     |> execute
  #
  #   args.cmd
  #
  # end

end
