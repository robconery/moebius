defmodule MoebiusInsertTest do
  use ExUnit.Case
  use Timex
  import Moebius.Query

  setup_all do
    cmd = db(:users)
        |> insert_command(email: "test@test.com", first: "Test", last: "User")
    {:ok, cmd: cmd}
  end

  test "a basic user insert", %{cmd: cmd} do
    assert cmd.sql == "insert into users(email, first, last) values($1, $2, $3) returning *;"
  end

  test "a basic user insert has params set", %{cmd: cmd} do
    assert length(cmd.params) == 3
  end

  test "it actually works" do
    assert %{email: "test@test.com", first: "Test", id: _id, last: "User", profile: nil} =
      db(:users)
        |> insert(email: "test@test.com", first: "Test", last: "User")

  end

  # test "It works with dates" do
  #   {:ok, the_date} = Date.local |> DateFormat.format("%Y-%m-%d", :strftime)
  #   blurg= %Postgrex.Timestamp{year: 2013, month: 10, day: 12, hour: 0, min: 37, sec: 14, usec: 0}
  #   res = db(:users)
  #     |> insert(email: "testX@test.com", first: "Test", last: "User", last_login: blurg)
  #   IO.inspect res
  # end


end
