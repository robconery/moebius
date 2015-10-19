defmodule Moebius.BasicSelectTest do

  use ExUnit.Case
  import Moebius.Query

  test "a basic select *" do

    cmd = dataset(:users)
        |> build(type: :select)

    assert cmd.sql == "select * from users;"
  end

  test "a basic select with columns" do

    cmd = dataset(:users, "first, last")
        |> build(type: :select)

    assert cmd.sql == "select first, last from users;"
  end

  test "a basic select with where" do
    cmd = dataset(:users)
        |> filter(id: 1, name: "Steve")
        |> build(type: :select)

    assert cmd.sql == "select * from users where id = $1 and name = $2;"
  end

  test "a basic select with a where string" do
    cmd = dataset(:users)
        |> filter("name=$1 OR thing=$2", ["Steve", "Bill"])
        |> build(type: :select)

    assert cmd.sql == "select * from users where name=$1 OR thing=$2;"
  end

  test "a basic select with a where string and no parameters" do
    cmd = dataset(:users)
        |> filter("id > 100")
        |> build(type: :select)

    assert cmd.sql == "select * from users where id > 100;"
  end

  test "a basic select with where and order" do
    cmd = dataset(:users)
        |> filter(id: 1, name: "Steve")
        |> sort(:name, :desc)
        |> build(type: :select)

    assert cmd.sql == "select * from users where id = $1 and name = $2 order by name desc;"
  end

  test "a basic select with where and order and limit without skip" do
    cmd = dataset(:users)
        |> filter(id: 1, name: "Steve")
        |> sort(:name, :desc)
        |> limit(10)
        |> build(type: :select)

    assert cmd.sql == "select * from users where id = $1 and name = $2 order by name desc limit 10;"
  end

  test "a basic select with where and order and limit with offset" do
    cmd = dataset(:users)
        |> filter(id: 1, name: "Steve")
        |> sort(:name, :desc)
        |> limit(10)
        |> offset(2)
        |> build(type: :select)

    assert cmd.sql == "select * from users where id = $1 and name = $2 order by name desc limit 10 offset 2;"
  end

end
