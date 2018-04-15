defmodule MoebiusPoolTest do
  use ExUnit.Case

  alias Moebius, as: Moebius

  test "basic method using connection pool" do
    1..20
    |> Enum.map(fn i -> getMyShit() end)
    |> Enum.each(fn task -> awaitMyShit(task) end)
  end

  defp getMyShit() do
    # args = %{sql: "select * from users", params: nil}
    Task.async(fn -> Moebius.connect() end)
  end

  defp awaitMyShit(task) do 
        {:ok, pid} = task |> Task.await(5000)
        assert pid
        # {:ok, cols, rows} = :epgsql.equery(pid, "select * from users")
        IO.inspect pid
  end

end