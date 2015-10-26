defmodule Moebius.ConnectionReleaseTest do
  use ExUnit.Case
  import Moebius.DocumentQuery

  setup do
    "delete from people"
      |> Moebius.Query.run
    {:ok, res: true}
  end

  # test "loading 100 at once" do
  #   res = write_benchmark(100)
  #   IO.puts "Finished"
  # end
  #
  # test "loading 1000 at once" do
  #   res = write_benchmark(1000)
  #   IO.puts "Finished"
  # end

  def people(qty) do
    Enum.map(1..qty, &(
      [
        first_name: "FirstName #{&1}",
        last_name: "LastName #{&1}",
        address: "666 SW Pine St.",
        city: "Portland",
        state: "OR",
        zip: "97209" ]))
  end

  def write_benchmark(qty) do
    people(qty)
    |> Enum.map(fn(p) ->
      db(:people)
        |> save(p)
    end)
  end
end
