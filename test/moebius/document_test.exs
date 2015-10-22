defmodule Moebius.DocTest do

  use ExUnit.Case
  import Moebius.DocumentQuery

  setup do
    "delete from user_docs;" |> Moebius.Query.run
    doc = [email: "steve@test.com", first: "Steve", money_spent: 500, pets: ["poopy", "skippy"]]
    res = :user_docs
      |> db()
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
      :user_docs
      |> db()
      |> insert(doc)
      |> execute(:single)
  end

  test "a simple insert as a string" do
    doc = ~s({"email": "steve@test.com"})

    assert %{email: "steve@test.com", id: _id} =
      :user_docs
      |> db()
      |> insert(doc)
      |> execute(:single)
  end

  test "a simple document query with the DocumentQuery lib" do
    assert %{email: "steve@test.com", id: _id} =
      :user_docs
      |> db()
      |> select
      |> execute(:single)
  end

  test "updating a document", %{res: res} do
    change = %{email: "blurgh@test.com"}
    assert %{email: "blurgh@test.com", id: _id} =
      :user_docs
      |> db()
      |> update(change, res.id)
      |> execute(:single)
  end

  test "the save shortcut inserts a document without an id" do
    new_doc = %{email: "new_person@test.com"}
    assert %{email: "new_person@test.com", id: _id} =
      :user_docs
      |> db()
      |> save(new_doc)
  end

  test "the save shortcut works updating a document", %{res: res} do
    change = %{email: "blurgh@test.com"}
    assert %{email: "blurgh@test.com", id: _id} =
      :user_docs
      |> db()
      |> save(change)
  end

  test "delete works with just an id", %{res: res} do
    res = :user_docs
      |> db()
      |> delete(res.id)
      |> execute(:single)

    assert res.id
  end

  test "delete works with criteria", %{res: res} do

    res = :user_docs
      |> db()
      |> contains(email: res.email)
      |> delete()
      |> execute()

    assert length(res) > 0
  end

  test "select works with filter", %{res: res} do

    return = :user_docs
      |> db()
      |> contains(email: res.email)
      |> select()
      |> execute(:single)

    assert return.email == res.email
  end

  test "select works with string criteria", %{res: res} do
    return = :user_docs
      |> db()
      |> filter("body -> 'email' = $1", res.email)
      |> select()
      |> execute(:single)

    assert return.email == res.email
  end

  test "select works with basic criteria", %{res: res} do

    return = :user_docs
      |> db()
      |> filter(:money_spent, ">", 100)
      |> select
      |> execute()

    assert length(return) > 0
  end

  test "select works with existence operator", %{res: res} do

    return = :user_docs
      |> db()
      |> exists(:pets, "poopy")
      |> first()

    assert return.id == res.id
  end
end
