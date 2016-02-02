defmodule Moebius.ConnectionTest do
  use ExUnit.Case

  test "the TestDb connects and runs" do
    res = "select * from date_night" |> TestDb.run
    assert length(res) > 0
  end

  test "connecting directly works as well" do
    {:ok, pid} = Moebius.Database.start_link(database: "meebuss")
    cmd = %Moebius.QueryCommand{sql: "select * from date_night", conn: pid}
    res = Moebius.Database.execute(cmd) |> Moebius.Transformer.to_list
    assert length(res) > 0
  end

end
