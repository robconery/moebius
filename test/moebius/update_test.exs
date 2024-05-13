defmodule Moebius.UpdateTest do
  use ExUnit.Case

  import Moebius.Query

  setup_all do
    cmd =
      db(:users)
      |> filter(id: 1)
      |> update(email: "maggot@test.com")

    {:ok, cmd: cmd}
  end

  test "a basic user update", %{cmd: cmd} do
    assert cmd.sql == "update users set email = $2 where id = $1 returning *;"
    assert length(cmd.params) == 2
    assert cmd.params == [1, "maggot@test.com"]
  end

  test "a basic user insert has params set", %{cmd: cmd} do
    assert length(cmd.params) == 2
  end

  test "a bulk update with a string filter" do
    cmd =
      db(:users)
      |> filter("id > 100")
      |> update(email: "test@test.com")

    assert cmd.sql == "update users set email = $1 where id > 100 returning *;"
    assert length(cmd.params) == 1
  end

  test "a bulk update with a string filter and params" do
    cmd =
      db(:users)
      |> filter("email LIKE %$1", "test")
      |> update(email: "ox@test.com")

    assert cmd.sql == "update users set email = $2 where email LIKE %$1 returning *;"
    assert length(cmd.params) == 2
    assert cmd.params == ["test", "ox@test.com"]
  end


  test "basic update with 'in' filter" do
    names = ["Super", "Mike"]
    cmd =
      db(:users)
      |> filter(:first, in: names)
      |> update(roles: ["newrole"])

    assert cmd.sql == "update users set roles = $3 where first IN($1, $2) returning *;"
    assert length(cmd.params) == 3
    assert cmd.params == names ++ [["newrole"]]
  end


  test "basic update with '>' filter" do
    cmd =
      db(:users)
      |> filter(:order_count, gt: 5)
      |> update(roles: ["newrole"])
    assert cmd.sql == "update users set roles = $2 where order_count > $1 returning *;"
    assert length(cmd.params) == 2
    assert cmd.params == [5, ["newrole"]]
  end



  # TODO: Move this to date tests

  # test "it actually works" do
  #     res = db(:date_night)
  #       |> filter(id: 1)
  #       |> update(date: :calendar.local_time)
  #       |> TestDb.run
  #
  #     assert res.date
  # end
end
