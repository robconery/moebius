defmodule Moebius.ExplainTest do
  use ExUnit.Case
  import Moebius.Query

  setup do
    Moebius.TestData.reset_users!()
    :ok
  end

  test "returns the plan Postgres will use" do
    assert {:ok, plan} = db(:users) |> filter(email: "a@test.com") |> TestDb.explain()

    assert plan =~ "users_email_key"
    assert plan =~ "cost="
  end

  test "a filter on an unindexed column is a sequential scan" do
    assert {:ok, plan} = db(:users) |> filter(first: "Rob") |> TestDb.explain()
    assert plan =~ "Seq Scan on users"
  end

  test "analyze runs the query but keeps none of its writes" do
    assert {:ok, plan} =
             db(:users) |> insert(email: "explained@test.com") |> TestDb.explain(analyze: true)

    assert plan =~ "actual time="
    assert {:ok, %{count: 0}} = db(:users) |> count() |> TestDb.run()
  end

  test "document queries can be explained" do
    TestDb.run("drop table if exists explain_docs")
    TestDb.create_document_table(:explain_docs)

    assert {:ok, plan} =
             Moebius.DocumentQuery.db(:explain_docs)
             |> Moebius.DocumentQuery.contains(sku: "x")
             |> TestDb.explain()

    assert plan =~ "explain_docs"
  end

  test "an invalid query is an error" do
    assert {:error, "relation \"nope\" does not exist"} = db(:nope) |> TestDb.explain()
  end
end
