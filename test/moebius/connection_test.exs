defmodule Moebius.ConnectionTest do
  use ExUnit.Case
  import Moebius.Query

  test "Extensions etc are loaded with get_connection" do
    opts = Moebius.parse_connection("postgresql://rob@localhost/meebuss")
    assert Keyword.has_key?(opts, :database)
  end
  test "A tuple list is turned into a keyword list" do
    res = {:database, "bonk"} |> TestDb.prepare_extensions
    assert Keyword.keyword?(res)
  end
  # test "Moebius starts as an app" do
  #   res = db(:users) |> Moebius.Db.first
  #   assert res.id
  # end
end
