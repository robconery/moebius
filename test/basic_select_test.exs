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

  test "a basic select with where and order" do
    cmd = dataset(:users)
        |> filter(id: 1, name: "Steve")
        |> sort(:name, :desc)
        |> build(type: :select)

    assert cmd.sql == "select * from users where id = $1 and name = $2 order by name desc;"
  end

end
