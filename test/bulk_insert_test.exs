defmodule Moebius.BulkInsertTest do
  use ExUnit.Case
  import Moebius.Commands

  test "it calls the right method" do
    args = [
      %{email: "test@test.com"},
      %{email: "test2@test.com"}
    ]
    cmd = insert args, :users
    IO.inspect(cmd)
  end
end
