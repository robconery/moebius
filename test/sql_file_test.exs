defmodule Moebius.SQLFileTest do
  use ExUnit.Case
  import Moebius.Query

  test "a single file is loaded" do
    cmd = sql_file(:simple, 1)
    assert cmd.sql == "select * from users where id=$1;"
    assert length(cmd.params) == 1
  end

  test "a cte can be loaded and run" do
    {:ok, res} = sql_file(:cte, "test@test.com")
      |> execute
      |> to_single

    assert res.id > 0
  end
end
