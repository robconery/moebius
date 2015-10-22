defmodule Moebius.TransactionTest do

  use ExUnit.Case

  import Moebius.Query

  test "queuing a transaction" do
    assert %{email: "tx@test.com", first: "Rob", last: "Blob", id: _id} =
      begin
        |> db(:users)
        |> insert(email: "tx@test.com", first: "Rob", last: "Blob")
        |> commit
  end

end
