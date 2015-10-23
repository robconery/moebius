defmodule Moebius.AggregateTest do
  use ExUnit.Case
  import Moebius.Query

  test "count returns integer" do
    res = db(:useraas)
      |> count

    assert res.count > 1
  end
end
