defmodule Moebius.DeleteTest do
  use ExUnit.Case
  import Moebius.Query

  test "a simple delete" do
    cmd = :users
      |> db()
      |> filter(id: 1)
      |> delete

    assert cmd.sql == "delete from users where id = $1 returning *;"
    assert length(cmd.params) == 1
  end

  test "a bulk delete with no params" do
    cmd = :users
      |> db()
      |> filter("id > 100")
      |> delete

    assert cmd.sql == "delete from users where id > 100 returning *;"
    assert length(cmd.params) == 0
  end

  test "a bulk delete with a single param" do
    cmd = :users
      |> db()
      |> filter("id > $1", 1)
      |> delete

    assert cmd.sql == "delete from users where id > $1 returning *;"
    assert length(cmd.params) == 1
  end
end
