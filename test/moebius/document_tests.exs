defmodule Moebius.DocTest do

  use ExUnit.Case
  import Moebius.DocumentQuery
  setup do
    "delete from user_docs;" |> Moebius.Query.run
    doc = [email: "steve@test.com", first: "Steve"]
    {:ok, res} = db(:user_docs)
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
    res = db(:user_docs)
      |> insert(doc)
      |> execute(:single)

    case res do
      {:ok, res} -> assert res.email == "steve@test.com"
      {:error, err} -> IO.inspect(err); flunk "No good"
    end
  end

  test "a simple insert as a string" do
    doc = "{\"email\":\"steve@test.com\"}"
    res = db(:user_docs)
      |> insert(doc)
      |> execute(:single)

    case res do
      {:ok, res} -> assert res.email == "steve@test.com"
      {:error, err} -> IO.inspect(err); flunk "No good"
    end
  end

  test "a simple document query with the DocumentQuery lib" do

    {:ok, res} = db(:user_docs)
      |> select
      |> execute(:single)

    assert res.email == "steve@test.com"
  end
  # test "a simple document query with the all shortcut" do
  #
  #   {:ok, res} = db(:user_docs)
  #     |> all
  #
  #   assert res.profile.twitter
  # end
  # test "a simple document query with a contains and the first shortcut" do
  #
  #   res = db(:user_docs)
  #     |> contains(email: "test@test.com")
  #     |> first
  #
  #   case res do
  #     {:ok, []} -> flunk "No results came back"
  #     {:ok, res} -> assert res.profile.twitter
  #     {:error, err} -> IO.inspect(err)
  #   end
  # end
  #
  # test "adding a document as a list" do
  #   doc = [email: "steve@test.com", first: "Steve"]
  #   res = db(:user_docs)
  #     |> insert(doc)
  #     |> execute
  #
  #   case res do
  #     {:ok, []} -> flunk "No results came back"
  #     {:ok, res} -> assert res.email == "steve@test.com"
  #     {:error, err} -> IO.inspect(err); flunk "No good"
  #   end
  # end
  #
  # test "adding a document as a map" do
  #   doc = %{email: "steve@test.com", first: "Steve"}
  #   res = db(:user_docs)
  #     |> insert(doc)
  #     |> execute
  #
  #   case res do
  #     {:ok, []} -> flunk "No results came back"
  #     {:ok, res} -> assert res.email == "steve@test.com"
  #     {:error, err} -> IO.inspect(err); flunk "No good"
  #   end
  # end
  #
  # test "adding a document as a string" do
  #   doc = '{"email":"steve@test.com"}'
  #   res = db(:user_docs)
  #     |> insert(doc)
  #     |> execute
  #
  #   case res do
  #     {:ok, []} -> flunk "No results came back"
  #     {:ok, res} -> assert res.email == "steve@test.com"
  #     {:error, err} -> IO.inspect(err); flunk "No good"
  #   end
  # end

end
