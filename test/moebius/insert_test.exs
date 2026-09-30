defmodule Moebius.InsertTest do
  use ExUnit.Case
  import Moebius.Query

  setup do
    Moebius.TestData.reset_users!()
    :ok
  end

  test "builds an insert with a placeholder per column" do
    cmd = db(:users) |> insert(email: "test@test.com", first: "Test", last: "User")

    assert cmd.sql == "insert into users(email, first, last) values($1, $2, $3) returning *;"
    assert cmd.params == ["test@test.com", "Test", "User"]
    assert cmd.type == :insert
  end

  test "an empty insert raises instead of building invalid SQL" do
    assert_raise ArgumentError, ~r/at least one column/, fn -> db(:users) |> insert([]) end
  end

  test "returns the inserted row, defaults included" do
    assert {:ok,
            %{
              email: "test@test.com",
              first: "Test",
              last: "User",
              id: id,
              order_count: 10,
              profile: nil,
              roles: nil
            }} =
             db(:users)
             |> insert(email: "test@test.com", first: "Test", last: "User")
             |> TestDb.run()

    assert is_integer(id)
  end

  test "returns an error on a constraint violation" do
    {:ok, _} = db(:users) |> insert(email: "dupe@test.com") |> TestDb.run()

    assert {:error, "duplicate key value violates unique constraint \"users_email_key\""} =
             db(:users) |> insert(email: "dupe@test.com") |> TestDb.run()
  end

  test "json and array columns round-trip" do
    assert {:ok, %{profile: %{"theme" => "dark"}, roles: ["admin", "dev"]}} =
             db(:users)
             |> insert(email: "json@test.com", profile: %{theme: "dark"}, roles: ["admin", "dev"])
             |> TestDb.run()
  end
end
