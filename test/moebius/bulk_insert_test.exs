defmodule Moebius.BulkInsertTest do
  use ExUnit.Case
  import Moebius.Query

  setup do
    TestDb.run("drop table if exists people")

    TestDb.run("""
    create table people (
      id serial primary key,
      first_name text not null,
      last_name text not null,
      address text null,
      city text null,
      state text null,
      zip text null
    );
    """)

    :ok
  end

  describe "bulk_insert/2" do
    test "splits large inserts into batches under the parameter limit" do
      %Moebius.CommandBatch{commands: commands} = db(:people) |> bulk_insert(people(5000))

      # 6 columns per row, so each command carries at most 20,000 / 6 = 3,333 rows
      assert [first, second] = commands
      assert length(first.params) == 3333 * 6
      assert length(second.params) == (5000 - 3333) * 6
    end

    test "builds one insert with a placeholder per value" do
      %Moebius.CommandBatch{commands: [cmd]} = db(:people) |> bulk_insert(people(2))

      assert cmd.sql ==
               "insert into people(first_name, last_name, address, city, state, zip) " <>
                 "values ($1,$2,$3,$4,$5,$6),($7,$8,$9,$10,$11,$12);"

      assert Enum.take(cmd.params, 2) == ["FirstName 1", "LastName 1"]
    end

    test "inserts every row outside a transaction" do
      results = db(:people) |> bulk_insert(people(5000)) |> TestDb.run_batch()

      assert [{:ok, _}, {:ok, _}] = results
      assert people_count() == 5000
    end

    test "inserts every row within a transaction" do
      results = db(:people) |> bulk_insert(people(5000)) |> TestDb.transact_batch()

      assert [{:ok, _}, {:ok, _}] = results
      assert people_count() == 5000
    end

    test "writes nothing when one row fails inside a transaction" do
      result = db(:people) |> bulk_insert(flawed_people(4)) |> TestDb.transact_batch()

      assert {:error,
              "null value in column \"first_name\" of relation \"people\" violates not-null constraint"} ==
               result

      assert people_count() == 0
    end
  end

  defp people_count do
    {:ok, %{count: count}} = db(:people) |> count() |> TestDb.run()
    count
  end

  defp people(qty) do
    Enum.map(
      1..qty,
      &[
        first_name: "FirstName #{&1}",
        last_name: "LastName #{&1}",
        address: "666 SW Pine St.",
        city: "Portland",
        state: "OR",
        zip: "97209"
      ]
    )
  end

  # the last row breaks the first_name not-null constraint
  defp flawed_people(qty) do
    people(qty - 1) ++
      [
        [
          first_name: nil,
          last_name: nil,
          address: nil,
          city: "Nowhere",
          state: "XX",
          zip: "00000"
        ]
      ]
  end
end
