defmodule MoebiusInsertTest do
  use ExUnit.Case

  import Moebius.Query

  setup_all do
    cmd =
      db(:users)
      |> insert(email: "test@test.com", first: "Test", last: "User")

    {:ok, cmd: cmd}
  end

  test "a basic user insert", %{cmd: cmd} do
    assert cmd.sql == "insert into users(email, first, last) values($1, $2, $3) returning *;"
  end

  test "a basic user insert has params set", %{cmd: cmd} do
    assert length(cmd.params) == 3
  end

  test "it actually works" do
    assert {:ok, %{email: "test@test.com", first: "Test", id: _id, last: "User", profile: nil}} =
             db(:users)
             |> insert(email: "test@test.com", first: "Test", last: "User")
             |> TestDb.run()
  end
end
