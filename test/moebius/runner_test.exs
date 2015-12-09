defmodule Moebius.RunnerTest do
  use ExUnit.Case

  import Moebius.Query

   setup do
     "delete from people;" |> Moebius.Query.run
     {:ok, res: true}
   end

  test "loading 100 at once" do
    assert 100 = write_benchmark(100) |> Enum.count
  end

  test "loading 1000 at once" do
    assert 1000 = write_benchmark(1000) |> Enum.count
  end

  # This passes but does slow the test suite down
  # test "loading 10000 at once" do
  #   assert 10000 = write_benchmark(10000) |> Enum.count
  # end

  defp people(qty) do
    Enum.map(1..qty, &(
      [
        first_name: "FirstName #{&1}",
        last_name: "LastName #{&1}",
        address: "666 SW Pine St.",
        city: "Portland",
        state: "OR",
        zip: "97209" ]))
  end

  defp write_benchmark(qty) do
    people(qty)
    |> Enum.map(&save/1)
  end

  defp save(record) do
    db(:people)
    |> insert_command(record)
    |> execute
  end
end
