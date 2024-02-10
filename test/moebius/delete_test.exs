defmodule Moebius.DeleteTest do
  use ExUnit.Case

  import Moebius.Query

  test "a simple delete" do
    cmd =
      db(:users)
      |> filter(id: 1)
      |> delete

    assert cmd.sql == "delete from users where id = $1;"
    assert length(cmd.params) == 1
  end

  test "a bulk delete with no params" do
    cmd =
      db(:users)
      |> filter("id > 100")
      |> delete

    assert cmd.sql == "delete from users where id > 100;"
    assert Enum.empty?(cmd.params)
  end

  test "a bulk delete with a single param" do
    cmd =
      db(:users)
      |> filter("id > $1", 1)
      |> delete

    assert cmd.sql == "delete from users where id > $1;"
    assert length(cmd.params) == 1
  end

  test "it actually works" do
    {:ok, res} =
      db(:logs)
      |> filter("id > $1", 1)
      |> delete
      |> TestDb.run()

    assert res.deleted
  end
end
