defmodule PoopDb do
  use Moebius.Database
end
defmodule Moebius.ConnectionTest do
  use ExUnit.Case
  #import Moebius.Query
  # import Moebius.DocumentQuery
  #
  # test "Extensions etc are loaded with get_connection" do
  #   opts = Moebius.parse_connection("postgresql://rob@localhost/meebuss")
  #   assert Keyword.has_key?(opts, :database)
  # end
  #
  # test "A tuple list is turned into a keyword list" do
  #   res = {:database, "bonk"} |> TestDb.prepare_extensions
  #   assert Keyword.keyword?(res)
  # end
  #
  # test "A supervised worker starts and runs" do
  #   worker = Supervisor.Spec.worker(PoopDb, [Moebius.get_connection])
  #   Supervisor.start_link [worker], strategy: :one_for_one
  #   res = db(:clowns) |> PoopDb.save(%{name: "Skuppy"})
  #   assert res.id
  # end
  # test "Moebius starts as an app" do
  #   res = db(:users) |> Moebius.Db.first
  #   assert res.id
  # end
end
