defmodule Moebius.DateTests do
  use ExUnit.Case

  setup_all do
    res = "select * from date_night" |> TestDb.all

    {:ok, data: res}
  end

  test "It returns the dates", %{data: res} do
    IO.inspect res
    assert length(res) == 4
  end
end
