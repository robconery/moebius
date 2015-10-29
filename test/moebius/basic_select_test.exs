defmodule Moebius.BasicSelectTest do

  use ExUnit.Case
  import Moebius.Query

  setup do
    db(:logs) |> delete
    db(:users) |> delete
    db(:users) |> insert(email: "friend@test.com")
    db(:users) |> insert(email: "enemy@test.com")

    {:ok, res: true}
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

  test "a basic select with where" do
    cmd = db(:users)
        |> filter(id: 1, name: "Steve")
        |> select_command

    assert cmd.sql == "select * from users where id = $1 and name = $2;"
  end

  test "a basic select with a where string" do
    cmd = db(:users)
        |> filter("name=$1 OR thing=$2", ["Steve", "Bill"])
        |> select_command

    assert cmd.sql == "select * from users where name=$1 OR thing=$2;"
  end

  test "a basic select with a where string and no parameters" do
    cmd = db(:users)
        |> filter("id > 100")
        |> select_command

    assert cmd.sql == "select * from users where id > 100;"
  end

  test "a basic select with where and order" do
    cmd = db(:users)
        |> filter(id: 1, name: "Steve")
        |> sort(:name, :desc)
        |> select_command

    assert cmd.sql == "select * from users where id = $1 and name = $2 order by name desc;"
  end

  test "a basic select with where and order and limit without skip" do
    cmd = db(:users)
        |> filter(id: 1, name: "Steve")
        |> sort(:name, :desc)
        |> limit(10)
        |> select_command

    assert cmd.sql == "select * from users where id = $1 and name = $2 order by name desc limit 10;"
  end

  test "a basic select with where and order and limit with offset" do

    cmd = db(:users)
        |> filter(id: 1, name: "Steve")
        |> sort(:name, :desc)
        |> limit(10)
        |> offset(2)
        |> select_command

    assert cmd.sql == "select * from users where id = $1 and name = $2 order by name desc limit 10 offset 2;"
  end

  test "a simple IN query" do
    cmd = db(:users)
        |> filter(:name, ["mark", "biff", "skip"])
        |> select_command

    assert cmd.sql == "select * from users where name IN($1, $2, $3);"
    assert length(cmd.params) == 3
  end

  test "a simple IN query, specified" do
    cmd = db(:users)
        |> filter(:name, in: ["mark", "biff", "skip"])
        |> select_command

    assert cmd.sql == "select * from users where name IN($1, $2, $3);"
    assert length(cmd.params) == 3
  end

  test "a simple NOT IN query, specified" do
    cmd = db(:users)
        |> filter(:name, not_in: ["mark", "biff", "skip"])
        |> select_command

    assert cmd.sql == "select * from users where name NOT IN($1, $2, $3);"
    assert length(cmd.params) == 3
  end

  test "first returns first" do
    res = db(:users)
      |> first

    assert res.email == "friend@test.com"
  end

  test "first returns nil when no match" do
    res = db(:users)
      |> filter(id: 10000)
      |> first

    assert res == nil
  end

  test "last returns last" do
    res = db(:users)
      |> last(:id)

    assert res.email == "enemy@test.com"
  end

  test "a basic query with a string parameter" do

    res = db(:users)
      |> filter("email LIKE $1", "%test.com%")
      |> to_list

    assert length(res) > 0

  end

end
