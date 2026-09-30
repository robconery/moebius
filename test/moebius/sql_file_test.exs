defmodule Moebius.SQLFileTest do
  use ExUnit.Case
  import Moebius.Query

  setup do
    Moebius.TestData.reset_users!()
    :ok
  end

  test "sql_file_command/2 loads the file and wraps a single param" do
    cmd = sql_file_command(:simple, 1)

    assert cmd.sql == "select * from users where id=$1;"
    assert cmd.params == [1]
  end

  test "sql_file/2 runs a CTE that writes to two tables" do
    assert {:ok, %{email: "blurgg@test.com", id: id}} =
             sql_file(:cte, "blurgg@test.com") |> TestDb.first()

    assert {:ok, [%{user_id: ^id, log: "New User added"}]} = db(:logs) |> TestDb.run()
  end

  test "a missing file raises" do
    assert_raise File.Error, fn -> sql_file_command(:no_such_file) end
  end
end
