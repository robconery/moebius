defmodule Moebius.PoolTest do
  use ExUnit.Case

  describe "Connection bits" do
    test "return a pid when using URL" do
      pid = Moebius.Pool.Connection.get("postgres://localhost/meebuss")
      assert pid != nil
    end
    test "return a pid when using just a database" do
      pid = Moebius.Pool.Connection.get(database: "meebuss")
      assert pid != nil
    end
    test "return a pid when specifying host" do
      pid = Moebius.Pool.Connection.get(host: "localhost", database: "meebuss")
      assert pid != nil
    end
  end
end