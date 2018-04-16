defmodule MoebiusPoolTest do
  use ExUnit.Case

  alias Moebius, as: Moebius

  test "basic method using connection pool" do
    1..10
    |> Enum.map(fn i -> getMyShit() end)
    |> Enum.each(fn task -> awaitMyShit(task) end)
  end

  defp getMyShit() do
    # args = %{sql: "select * from users", params: nil}
    Task.async(fn -> Moebius.connect() end)
  end

  defp awaitMyShit(task) do 
        {:ok, cols, rows, pid} = Moebius.Runner.execute("select * from users where email like $1", ["friend@test.com"])
        IO.inspect rows
        IO.inspect pid
  end

end