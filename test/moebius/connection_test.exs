defmodule ConnectionTest do
  use ExUnit.Case

  test "epgsql connects" do
    {:ok, pid} = Moebius.Runner.connect
    refute pid == nil
  end

end
