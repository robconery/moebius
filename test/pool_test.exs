defmodule Moebius.ConnectionTest do
  use ExUnit.Case


  describe "A pool worker" do
    test "Starts with just a simple connection" do
      url = "postgres://localhost/meebuss"
      {:ok, res} = Moebius.Pool.Worker.start_link connection: url
      assert res
    end
  end

  describe "Calling a TX using the pool" do
    test "It will return a pid" do
      res = :poolboy.transaction(
        :default,
        fn(pid) -> pid end,
        :infinity
      )
      assert res != nil
    end
  end
end