defmodule Moebius.FunctionTest do

  use ExUnit.Case
  import Moebius.Query

  test "a simple function call is constructed" do

    cmd = db(:users)
          |> function(:all_users)


    assert cmd.sql == "select * from all_users();"
  end

  test "a simple function call is constructed with args" do

    cmd = db(:users)
          |> function(:all_users, name: "steve")


    assert cmd.sql == "select * from all_users($1);"
    assert length(cmd.params) == 1
  end
end
