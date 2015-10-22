defmodule Moebius.UpdateTest do
  use ExUnit.Case


  import Moebius.Query

  setup_all do

    cmd = :users
        |> db()
        |> filter(id: 1)
        |> update(email: "maggot@test.com")

    {:ok, cmd: cmd}
  end

  test "a basic user update", %{cmd: cmd} do
    assert cmd.sql == "update users set email = $1 where id = $2 returning *;"
    assert length(cmd.params) == 2
  end

  test "a basic user insert has params set", %{cmd: cmd} do
    assert length(cmd.params) == 2
  end

  test "a bulk update with a string filter" do
    cmd = :users
        |> db()
        |> filter("id > 100")
        |> update(email: "test@test.com")

    assert cmd.sql == "update users set email = $1 where id > 100 returning *;"
    assert length(cmd.params) == 1
  end


  test "a bulk update with a string filter and params" do
    cmd = :users
        |> db()
        |> filter("email LIKE %$2", "test")
        |> update(email: "ox@test.com")

    assert cmd.sql == "update users set email = $1 where email LIKE %$2 returning *;"
    assert length(cmd.params) == 2
  end

  test "it actually works" do
    assert %{email: "maggot@test.com", first: "Rob", id: 1, last: "Blah", profile: nil} =
      :users
        |> db()
        |> filter(id: 1)
        |> update(email: "maggot@test.com")
        |> execute
  end
end
