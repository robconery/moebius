defmodule Moebius.QueryFilterTest do
  use ExUnit.Case

  doctest Moebius.QueryFilter

  import Moebius.QueryFilter

  setup context do
    predicates = context[:where] || ""
    params = context[:params] || []
    cmd = %Moebius.QueryCommand{table_name: 'users', where: predicates, params: params}
    {:ok, [query: cmd]}
  end

  test "a basic 'WHERE' statement", %{query: query} do
    query = filter(query, email: "test@test.com", company: "Test Company")

    assert " where email = $1 and company = $2" == query.where
    assert ["test@test.com", "Test Company"] == query.params
  end

  test "a 'WHERE' statement with binary criteria", %{query: query} do
    query = filter(query, "created_at > now()")

    assert " where created_at > now()" == query.where
    assert [] == query.params
  end

  test "a 'WHERE' statement with criteria and params", %{query: query} do
    query = filter(query, "email LIKE $1", "%test.com%")

    assert " where email LIKE $1" == query.where
    assert ["%test.com%"] == query.params
  end

  test "a 'WHERE' statement using 'IN'", %{query: query} do
    query = filter(query, :name, in: ["phillip", "lela", "bender"])

    assert " where name IN($1, $2, $3)" == query.where
    assert ["phillip", "lela", "bender"] == query.params
  end

  test "a 'WHERE' statement using 'NOT IN'", %{query: query} do
    query = filter(query, :name, not_in: ["phillip", "lela", "bender"])

    assert " where name NOT IN($1, $2, $3)" == query.where
    assert ["phillip", "lela", "bender"] == query.params
  end

  @tag where: " where email LIKE $1", params: ["test@test.com"]
  test "pipe multiple filters", %{query: query} do
    query = filter(query, :name, in: ["phillip", "lela", "bender"])

    assert " where email LIKE $1 and name IN($2, $3, $4)" == query.where
    assert ["test@test.com", "phillip", "lela", "bender"] == query.params
  end

  @tag where: " where name IN($1, $2, $3)", params: ["phillip", "lela", "bender"]
  test "pipe multiple filters when first predicate is 'IN'", %{query: query} do
    query = filter(query, "email LIKE $4", "%test.com%")

    assert " where name IN($1, $2, $3) and email LIKE $4" == query.where
    assert ["phillip", "lela", "bender", "%test.com%"] == query.params
  end

  @tag where: " where email LIKE $1", params: ["%test.com%"]
  test "pipe multiple filters when second predicate is 'NOT IN'", %{query: query} do
    query = filter(query, :name, not_in: ["phillip", "lela", "bender"])

    assert " where email LIKE $1 and name NOT IN($2, $3, $4)" == query.where
    assert ["%test.com%", "phillip", "lela", "bender"] == query.params
  end

  test "a basic select with a where string", %{query: query} do
    cmd = filter(query, "name=$1 OR thing=$2", ["Steve", "Bill"])
          |> Moebius.Query.select

    assert cmd.sql == "select * from users where name=$1 OR thing=$2;"
  end

end
