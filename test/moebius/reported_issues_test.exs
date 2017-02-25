defmodule Moebius.GithubIssues do
  use ExUnit.Case
  import Moebius.Query

  test "multiple filters #70" do
    db(:users)
      |> insert(first: "Super", last: "Filter", email: "superfilter@test.com")
      |> TestDb.run

    {:ok, res} = db(:users)
      |> filter(first: "Super")
      |> filter(last: "Filter")
      |> TestDb.run
    IO.inspect res
  end

  test "It can update an array column #80" do
    db(:users)
      |> insert(email: "array@test.com", first: "Test", last: "User", roles: ["admin"])
      |> TestDb.run

    {:ok, res: true}

    res = db(:users)
      |> filter(email: "array@test.com")
      |> update(roles: ["admin"])
      |> TestDb.run

    IO.inspect res
  end
end
