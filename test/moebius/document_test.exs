defmodule Moebius.DocTest do

  use ExUnit.Case
  import Moebius.DocumentQuery

  setup do
    "delete from user_docs;" |> Moebius.Query.run
    doc = [email: "steve@test.com", first: "Steve"]
    res = db(:user_docs)
      |> insert(doc)
      |> execute(:single)
    {:ok, res: res}
  end

  test "a simple insert as a list returns the record", %{res: res} do
    assert res.email == "steve@test.com"
  end

  test "a simple insert as a list returns the id", %{res: res} do
    assert res.id > 0
  end

  test "a simple insert as a map" do
    doc = %{email: "steve@test.com", first: "Steve"}

    assert %{email: "steve@test.com", first: "Steve", id: _id} =
      db(:user_docs)
        |> insert(doc)
        |> execute(:single)
  end

  test "a simple insert as a string" do
    doc = "{\"email\":\"steve@test.com\"}"

    assert %{email: "steve@test.com", id: _id} =
      db(:user_docs)
        |> insert(doc)
        |> execute(:single)
  end

  test "a simple document query with the DocumentQuery lib" do
    assert %{email: "steve@test.com", id: _id} =
      db(:user_docs)
        |> select
        |> execute(:single)
  end

  test "updating a document", %{res: res} do
    change = %{email: "blurgh@test.com"}
    assert %{email: "blurgh@test.com", id: _id} =
      db(:user_docs)
        |> update(change, res.id)
        |> execute(:single)

  end

  test "the save shortcut inserts a document without an id" do
    new_doc = %{email: "new_person@test.com"}
    assert %{email: "new_person@test.com", id: _id} =
      db(:user_docs)
        |> save(new_doc)
  end

  test "the save shortcut works updating a document", %{res: res} do
    change = %{email: "blurgh@test.com"}
    assert %{email: "blurgh@test.com", id: _id} =
      db(:user_docs)
        |> save(change)
  end

  test "delete works with just an id", %{res: res} do
    res = db(:user_docs)
      |> delete(res.id)
      |> execute(:single)

    assert res.id
  end

  test "delete works with criteria", %{res: res} do

    res = db(:user_docs)
      |> contains(email: res.email)
      |> delete
      |> execute

    assert length(res) > 0
  end

end
