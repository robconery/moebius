defmodule Moebius.FunctionTest do
  use ExUnit.Case
  import Moebius.Query

  test "a function call with no args" do
    cmd = function_command(:all_users)

    assert cmd.sql == "select * from all_users();"
    assert cmd.params == []
  end

  test "a function call with args gets a placeholder per arg" do
    cmd = function_command(:friends, ["mike", "jane"])

    assert cmd.sql == "select * from friends($1, $2);"
    assert cmd.params == ["mike", "jane"]
  end

  test "a single non-list arg is wrapped" do
    assert %{sql: "select * from lookup($1);", params: [42]} = function_command(:lookup, 42)
  end

  test "function/2 runs the function" do
    assert {:ok, [%{upper: "MOEBIUS"}]} = function(:upper, "moebius") |> TestDb.run()
  end
end
