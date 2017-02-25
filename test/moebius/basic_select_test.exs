defmodule Moebius.BasicSelectTest do

  use ExUnit.Case
  import Moebius.Query
  import TestDb

  setup do
    db(:logs) |> delete |> run
    db(:users) |> delete |> run
    {:ok, user} = db(:users) |> insert(email: "friend@test.com") |> run
    db(:users) |> insert(email: "enemy@test.com") |> run
    {:ok, res: user}
  end

  test "a basic select *" do

    cmd = db(:users)
        |> select

    assert cmd.sql == "select * from users;"
  end

  test "a basic select * using binary for tablename" do

    cmd = db("users")
        |> select

    assert cmd.sql == "select * from users;"
  end

  test "a basic select with columns" do

    cmd = db(:users)
        |> select("first, last")

    assert cmd.sql == "select first, last from users;"
  end

  test "a basic select with order" do
    cmd = db(:users)
        |> sort(:name, :desc)
        |> select

    assert cmd.sql == "select * from users order by name desc;"
  end

  test "a basic select with order and limit without skip" do
    cmd = db(:users)
        |> sort(:name, :desc)
        |> limit(10)
        |> select

    assert cmd.sql == "select * from users order by name desc limit 10;"
  end

  test "a basic select with order and limit with offset" do

    cmd = db(:users)
        |> sort(:name, :desc)
        |> limit(10)
        |> offset(2)
        |> select

    assert cmd.sql == "select * from users order by name desc limit 10 offset 2;"
  end

  test "first returns first" do
    {:ok, res} = db(:users)
      |> first

    assert res.email == "friend@test.com"
  end

  test "find returns a single record", %{res: user} do
    {:ok, found} = db(:users)
          |> find(user.id)

    assert found.id == user.id
  end

  test "filter returns a few records", %{res: user} do
    {:ok, found} = db(:users)
          |> filter(id: user.id)
          |> run

    assert length(found) > 0
  end

end
