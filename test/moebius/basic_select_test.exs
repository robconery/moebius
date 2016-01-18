defmodule Moebius.BasicSelectTest do

  use ExUnit.Case
  import Moebius.Query

  setup do
    db(:logs) |> delete
    db(:users) |> delete
    user = db(:users) |> insert(email: "friend@test.com")
    db(:users) |> insert(email: "enemy@test.com")

    {:ok, res: user}
  end

  test "a basic select *" do

    cmd = db(:users)
        |> select_command

    assert cmd.sql == "select * from users;"
  end

  test "a basic select * using binary for tablename" do

    cmd = db("users")
        |> select_command

    assert cmd.sql == "select * from users;"
  end

  test "a basic select with columns" do

    cmd = db(:users)
        |> select_command("first, last")

    assert cmd.sql == "select first, last from users;"
  end

  test "a basic select with order" do
    cmd = db(:users)
        |> sort(:name, :desc)
        |> select_command

    assert cmd.sql == "select * from users order by name desc;"
  end

  test "a basic select with order and limit without skip" do
    cmd = db(:users)
        |> sort(:name, :desc)
        |> limit(10)
        |> select_command

    assert cmd.sql == "select * from users order by name desc limit 10;"
  end

  test "a basic select with order and limit with offset" do

    cmd = db(:users)
        |> sort(:name, :desc)
        |> limit(10)
        |> offset(2)
        |> select_command

    assert cmd.sql == "select * from users order by name desc limit 10 offset 2;"
  end

  test "first returns first" do
    res = db(:users)
      |> first

    assert res.email == "friend@test.com"
  end

  test "last returns last" do
    res = db(:users)
      |> last(:id)

    assert res.email == "enemy@test.com"
  end

  test "find returns a single record", %{res: user} do
    found = db(:users)
          |> find(user.id)

    assert found.id == user.id
  end

end
