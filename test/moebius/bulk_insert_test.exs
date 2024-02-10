defmodule MoebiusBulkInsertTest do
  use ExUnit.Case

  # import Moebius.BulkInsert
  import Moebius.Query

  setup do
    "drop table if exists people" |> TestDb.run()

    "create table people (
      id serial primary key,
      first_name text not null,
      last_name text not null,
      address text null,
      city text null,
      state text null,
      zip text null
    );" |> TestDb.run()

    {:ok, res: true}
  end

  test "inserts a list of records outside a transaction" do
    data = 5000 |> people

    res =
      db(:people)
      |> bulk_insert(data)
      |> TestDb.run_batch()

    assert [{:ok, _result} | _other_results] = res
  end

  test "inserts a list of records within a transaction" do
    data = 5000 |> people

    res =
      db(:people)
      |> bulk_insert(data)
      |> TestDb.transact_batch()

    assert [{:ok, _result} | _other_results] = res
  end

  test "bulk insert fails as a transaction" do
    data = flawed_people(4)

    res =
      db(:people)
      |> bulk_insert(data)
      |> TestDb.transact_batch()

    assert {:error,
            "null value in column \"first_name\" of relation \"people\" violates not-null constraint"} ==
             res

    # no records were written to the db either...
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

  # tests for trans failures dur to constraint violations:
  defp flawed_people(qty) do
    p = Enum.reverse(people(qty - 1))

    flawed = [
      first_name: nil,
      last_name: nil,
      address: nil,
      city: "fucked city",
      state: "BumFuck",
      zip: "10011"
    ]

    Enum.reverse([flawed | p])
  end

  # tests for trans failures due to malformed inputs:
  # defp flawed_people(qty) do
  #   p = Enum.reverse(people(qty - 1))
  #   flawed = [
  #     first_name: "X",
  #     last_name: "Y",
  #     address: "Z",
  #     city: "fucked city",
  #     state: "BumFuck",
  #   ]
  #   Enum.reverse([flawed | p])
  # end
end
