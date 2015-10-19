defmodule Moebius.BasicSelectTest do

  use ExUnit.Case
  import Moebius.Query

  test "a basic select *" do

    cmd = db(:users)
        |> select

    assert cmd.sql == "select * from users;"
  end

  test "a basic select with columns" do

    cmd = db(:users, "first, last")
        |> select

    assert cmd.sql == "select first, last from users;"
  end

  test "a basic select with where" do
    cmd = db(:users)
        |> filter(id: 1, name: "Steve")
        |> select

    assert cmd.sql == "select * from users where id = $1 and name = $2;"
  end

  test "a basic select with a where string" do
    cmd = db(:users)
        |> filter("name=$1 OR thing=$2", ["Steve", "Bill"])
        |> select

    assert cmd.sql == "select * from users where name=$1 OR thing=$2;"
  end

  test "a basic select with a where string and no parameters" do
    cmd = db(:users)
        |> filter("id > 100")
        |> select

    assert cmd.sql == "select * from users where id > 100;"
  end

  test "a basic select with where and order" do
    cmd = db(:users)
        |> filter(id: 1, name: "Steve")
        |> sort(:name, :desc)
        |> select

    assert cmd.sql == "select * from users where id = $1 and name = $2 order by name desc;"
  end

  test "a basic select with where and order and limit without skip" do
    cmd = db(:users)
        |> filter(id: 1, name: "Steve")
        |> sort(:name, :desc)
        |> limit(10)
        |> select

    assert cmd.sql == "select * from users where id = $1 and name = $2 order by name desc limit 10;"
  end

  test "a basic select with where and order and limit with offset" do
    cmd = db(:users)
        |> filter(id: 1, name: "Steve")
        |> sort(:name, :desc)
        |> limit(10)
        |> offset(2)
        |> select

    assert cmd.sql == "select * from users where id = $1 and name = $2 order by name desc limit 10 offset 2;"
  end

  test "a simple IN query" do
    cmd = db(:users)
        |> filter(:name, ["mark", "biff", "skip"])
        |> select

    assert cmd.sql == "select * from users where name IN($1, $2, $3);"
    assert length(cmd.params) == 3
  end

  test "a simple IN query, specified" do
    cmd = db(:users)
        |> filter(:name, in: ["mark", "biff", "skip"])
        |> select

    assert cmd.sql == "select * from users where name IN($1, $2, $3);"
    assert length(cmd.params) == 3
  end
  test "a simple NOT IN query, specified" do
    cmd = db(:users)
        |> filter(:name, not_in: ["mark", "biff", "skip"])
        |> select

    assert cmd.sql == "select * from users where name NOT IN($1, $2, $3);"
    assert length(cmd.params) == 3
  end
end
