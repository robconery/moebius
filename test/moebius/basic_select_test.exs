defmodule Moebius.BasicSelectTest do
  use ExUnit.Case
  import Moebius.Query
  import TestDb

  setup do
    Moebius.TestData.reset_users!()
    {:ok, friend} = db(:users) |> insert(email: "friend@test.com") |> run()
    {:ok, _enemy} = db(:users) |> insert(email: "enemy@test.com") |> run()
    {:ok, friend: friend}
  end

  describe "select/2 SQL" do
    test "a basic select *" do
      assert db(:users) |> select() |> Map.get(:sql) == "select * from users;"
    end

    test "a binary table name" do
      assert db("users") |> select() |> Map.get(:sql) == "select * from users;"
    end

    test "columns as a string" do
      assert db(:users) |> select("first, last") |> Map.get(:sql) ==
               "select first, last from users;"
    end

    test "columns as a list" do
      assert db(:users) |> select([:first, :last]) |> Map.get(:sql) ==
               "select first, last from users;"
    end

    test "with order" do
      cmd = db(:users) |> sort(:name, :desc) |> select()

      assert cmd.sql == "select * from users order by name desc;"
    end

    test "with order and limit" do
      cmd = db(:users) |> sort(:name, :desc) |> limit(10) |> select()

      assert cmd.sql == "select * from users order by name desc limit 10;"
    end

    test "with order, limit and offset" do
      cmd = db(:users) |> sort(:name, :desc) |> limit(10) |> offset(2) |> select()

      assert cmd.sql == "select * from users order by name desc limit 10 offset 2;"
    end
  end

  describe "running selects" do
    test "first returns the first row of the sort" do
      assert {:ok, %{email: "friend@test.com"}} = db(:users) |> sort(:id) |> first()
    end

    test "first returns nil when nothing matches" do
      assert {:ok, nil} = db(:users) |> filter(email: "nobody@test.com") |> first()
    end

    test "find returns a single record", %{friend: friend} do
      assert {:ok, %{id: id, email: "friend@test.com"}} = db(:users) |> find(friend.id)
      assert id == friend.id
    end

    test "filter returns the matching records", %{friend: friend} do
      assert {:ok, [%{email: "friend@test.com"}]} = db(:users) |> filter(id: friend.id) |> run()
    end

    test "run with no filter returns every row" do
      {:ok, rows} = db(:users) |> run()

      assert rows |> Enum.map(& &1.email) |> Enum.sort() == ["enemy@test.com", "friend@test.com"]
    end
  end
end
