defmodule Moebius.DocumentTest do
  use ExUnit.Case
  import Moebius.DocumentQuery

  defmodule Candy do
    @moduledoc false
    defstruct id: nil, sticky: true, chocolate: "gooey"
  end

  setup do
    TestDb.run("delete from user_docs;")
    TestDb.run("drop table if exists monkies;")
    TestDb.run("drop table if exists artists;")

    {:ok, monkey} =
      db(:monkies)
      |> searchable([:name, :description])
      |> TestDb.save(%{sku: "stuff", name: "Chicken Wings", description: "duck dog lamb"})

    {:ok, steve} =
      db(:user_docs)
      |> TestDb.save(
        email: "steve@test.com",
        first: "Steve",
        money_spent: 500,
        pets: ["rex", "skippy"]
      )

    {:ok, steve: steve, monkey: monkey}
  end

  describe "document tables" do
    test "create_document_table/1 creates the table" do
      TestDb.run("drop table if exists vats;")

      assert TestDb.create_document_table(:vats) == {:ok, "Table created"}
      assert {:ok, []} = db(:vats) |> TestDb.run()
    end

    test "save creates the table if it doesn't exist" do
      assert {:ok, %{name: "Spiff", id: 1}} = db(:artists) |> TestDb.save(%{name: "Spiff"})
    end

    test "save creates the table even when an id is included" do
      assert {:ok, %{name: "jeff", id: 1}} = db(:artists) |> TestDb.save(%{name: "jeff", id: 100})
    end

    test "creating a document table twice is fine" do
      TestDb.run("drop table if exists vats;")

      assert {:ok, "Table created"} = TestDb.create_document_table(:vats)
      assert {:ok, "Table created"} = TestDb.create_document_table(:vats)
    end

    test "a schema-qualified document table gets valid index names" do
      TestDb.run("drop table if exists public.qualified_docs;")

      assert {:ok, %{name: "q"}} = db("public.qualified_docs") |> TestDb.save(%{name: "q"})

      assert {:ok,
              [
                %{indexname: "idx_public_qualified_docs"},
                %{indexname: "idx_public_qualified_docs_search"}
              ]} =
               TestDb.run(
                 "select indexname from pg_indexes where tablename = 'qualified_docs' and indexname like 'idx_%' order by 1"
               )
    end

    test "many processes can create the same table at once" do
      TestDb.run("drop table if exists racing_docs;")

      results =
        1..8
        |> Task.async_stream(fn n -> db(:racing_docs) |> TestDb.save(%{n: n}) end,
          max_concurrency: 8
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.all?(results, &match?({:ok, %{n: _}}, &1)), inspect(results)
      assert {:ok, docs} = db(:racing_docs) |> TestDb.run()
      assert length(docs) == 8
    end

    test "first creates the table if it doesn't exist" do
      assert {:ok, nil} = db(:artists) |> TestDb.first()
    end
  end

  describe "save/2 inserting" do
    test "a keyword list returns the saved document", %{steve: steve} do
      assert %{email: "steve@test.com", first: "Steve", money_spent: 500} = steve
      assert steve.pets == ["rex", "skippy"]
      assert is_integer(steve.id) and steve.id > 0
    end

    test "a map returns the saved document with an id" do
      assert {:ok, %{email: "new_person@test.com", id: id}} =
               db(:user_docs) |> TestDb.save(%{email: "new_person@test.com"})

      assert is_integer(id)
    end

    test "values with single quotes and nested maps round-trip" do
      thing = %{
        description: "Why walk when you can fly! You'll be the talk of the Martian skies!",
        name: "Johnny Liftoff Rocket Suit",
        price: 8_933_300,
        sku: "johnny-liftoff",
        vendor: %{name: "Martian Armaments, Ltd", slug: "martian-armaments"}
      }

      assert {:ok, saved} = db(:artists) |> TestDb.save(thing)
      assert saved.description == thing.description
      assert saved.vendor == %{name: "Martian Armaments, Ltd", slug: "martian-armaments"}
    end

    test "created_at and updated_at are set by the database and can't be overridden" do
      assert {:ok, saved} = db(:monkies) |> TestDb.save(%{name: "bip", updated_at: "nope"})
      assert %DateTime{} = saved.created_at
      assert saved.updated_at == saved.created_at
    end

    test "saving a struct returns the same struct type" do
      assert {:ok, %Candy{id: id, sticky: true, chocolate: "gooey"}} =
               db(:monkies) |> TestDb.save(%Candy{})

      assert is_integer(id)
    end
  end

  describe "save/2 updating" do
    test "a document with an id is updated in place", %{steve: steve} do
      assert {:ok, %{email: "blurgh@test.com", id: id}} =
               db(:user_docs) |> TestDb.save(%{email: "blurgh@test.com", id: steve.id})

      assert id == steve.id
      assert {:ok, [%{email: "blurgh@test.com"}]} = db(:user_docs) |> TestDb.run()
    end

    test "updated_at moves forward", %{steve: steve} do
      {:ok, updated} = db(:user_docs) |> TestDb.save(Map.put(steve, :first, "Steven"))

      assert updated.first == "Steven"
      assert DateTime.compare(updated.updated_at, steve.created_at) in [:gt, :eq]
    end

    test "searchable fields are indexed on save" do
      {:ok, _} =
        db(:monkies)
        |> searchable([:name, :description])
        |> TestDb.save(%{sku: "hot", name: "Buffalo Wings", description: "spicy"})

      assert {:ok, [%{name: "Buffalo Wings"}]} = db(:monkies) |> search("spicy") |> TestDb.run()
    end
  end

  describe "finding documents" do
    test "find returns the document by id", %{steve: steve} do
      assert {:ok, %{id: id, email: "steve@test.com"}} = db(:user_docs) |> TestDb.find(steve.id)
      assert id == steve.id
    end

    test "find returns created_at", %{monkey: monkey} do
      assert {:ok, %{name: "Chicken Wings", created_at: %DateTime{}}} =
               db(:monkies) |> TestDb.find(monkey.id)
    end

    test "find returns nil when the id doesn't exist" do
      assert {:ok, nil} = db(:monkies) |> TestDb.find(155_555)
    end

    test "run with no criteria returns every document" do
      assert {:ok, [%{email: "steve@test.com", id: _}]} = db(:user_docs) |> TestDb.run()
    end

    test "first returns a single document" do
      assert {:ok, %{email: "steve@test.com", id: _}} = db(:user_docs) |> TestDb.first()
    end

    test "contains/2 matches with the containment operator", %{steve: steve} do
      assert {:ok, %{id: id}} = db(:user_docs) |> contains(email: steve.email) |> TestDb.first()
      assert id == steve.id
    end

    test "contains/2 returns nil when nothing matches" do
      assert {:ok, nil} = db(:monkies) |> contains(email: "dog@dog.comdog") |> TestDb.first()
    end

    test "filter/3 with a string and a param", %{steve: steve} do
      assert {:ok, %{id: id}} =
               db(:user_docs) |> filter("body ->> 'email' = $1", steve.email) |> TestDb.first()

      assert id == steve.id
    end

    test "filter/4 with a field, an operator and a value" do
      assert {:ok, [%{email: "steve@test.com"}]} =
               db(:user_docs) |> filter(:money_spent, ">", 100) |> TestDb.run()

      assert {:ok, []} = db(:user_docs) |> filter(:money_spent, ">", 1000) |> TestDb.run()
    end

    test "exists/3 matches an element of an array", %{steve: steve} do
      assert {:ok, %{id: id}} = db(:user_docs) |> exists(:pets, "rex") |> TestDb.first()
      assert id == steve.id
    end

    test "sort, limit and offset combine" do
      {:ok, _} =
        db(:user_docs) |> TestDb.save(email: "rich@test.com", money_spent: 900, pets: ["rex"])

      assert {:ok, %{email: "rich@test.com"}} =
               db(:user_docs)
               |> exists(:pets, "rex")
               |> sort(:money_spent, :desc)
               |> limit(1)
               |> offset(0)
               |> TestDb.first()

      assert {:ok, [%{email: "steve@test.com"}]} =
               db(:user_docs)
               |> exists(:pets, "rex")
               |> sort(:money_spent, :desc)
               |> limit(1)
               |> offset(1)
               |> TestDb.run()
    end
  end

  describe "full text search" do
    test "search/2 uses the indexed search column" do
      assert {:ok, [%{name: "Chicken Wings"}]} = db(:monkies) |> search("duck") |> TestDb.run()
    end

    test "search/2 accepts plain search-box input" do
      assert {:ok, [%{name: "Chicken Wings"}]} =
               db(:monkies) |> search("duck lamb") |> TestDb.run()

      assert {:ok, []} = db(:monkies) |> search("O'Brien's") |> TestDb.run()
    end

    test "search/2 with for: and in: searches on the fly" do
      assert {:ok, [%{name: "Chicken Wings"}]} =
               db(:monkies) |> search(for: "duck", in: [:name, :description]) |> TestDb.run()
    end
  end

  describe "deleting documents" do
    test "delete/2 with an id returns the deleted document", %{steve: steve} do
      assert {:ok, %{id: id, email: "steve@test.com"}} =
               db(:user_docs) |> delete(steve.id) |> TestDb.first()

      assert id == steve.id
      assert {:ok, []} = db(:user_docs) |> TestDb.run()
    end

    test "delete/1 with criteria returns the deleted documents", %{steve: steve} do
      assert {:ok, [%{email: "steve@test.com"}]} =
               db(:user_docs) |> contains(email: steve.email) |> delete() |> TestDb.run()

      assert {:ok, []} = db(:user_docs) |> TestDb.run()
    end
  end
end
