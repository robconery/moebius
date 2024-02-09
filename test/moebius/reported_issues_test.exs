defmodule Moebius.GithubIssues do
  use ExUnit.Case
  import Moebius.Query

  test "multiple filters #70" do
    db(:users)
    |> insert(first: "Super", last: "Filter", email: "superfilter@test.com")
    |> TestDb.run()

    {:ok, res} =
      db(:users)
      |> filter(first: "Super")
      |> filter(last: "Filter")
      |> TestDb.first()

    assert(res.email == "superfilter@test.com")
  end

  test "It can update an array column #80" do
    db(:users)
    |> insert(email: "array@test.com", first: "Test", last: "User", roles: ["admin"])
    |> TestDb.run()

    {:ok, res: true}

    {:ok, res} =
      db(:users)
      |> filter(email: "array@test.com")
      |> update(roles: ["admin"])
      |> TestDb.first()

    # if we got here we're happy
    assert(res.email == "array@test.com")
  end

  # test "Filtering on NULL values from #35" do
  #   db(:users)
  #     |> insert(email: "null@test.com", first: "Test")
  #     |> TestDb.run
  #
  #   cmd = db(:users)
  #     |> filter(last: nil)
  #     |> TestDb.run
  #
  #   IO.inspect cmd
  #   #assert(res.email == "null@test.com")
  # end
end
