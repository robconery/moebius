defmodule Moebius.DeleteTest do
  use ExUnit.Case
  import Moebius.Query

  describe "delete/1 SQL" do
    test "a simple delete" do
      cmd = db(:users) |> filter(id: 1) |> delete()

      assert cmd.sql == "delete from users where id = $1;"
      assert cmd.params == [1]
    end

    test "a bulk delete with no params" do
      cmd = db(:users) |> filter("id > 100") |> delete()

      assert cmd.sql == "delete from users where id > 100;"
      assert cmd.params == []
    end

    test "a bulk delete with a single param" do
      cmd = db(:users) |> filter("id > $1", 1) |> delete()

      assert cmd.sql == "delete from users where id > $1;"
      assert cmd.params == [1]
    end
  end

  describe "running deletes" do
    setup do
      Moebius.TestData.reset_users!()
      {:ok, user} = db(:users) |> insert(email: "deleted@test.com") |> TestDb.run()

      for n <- 1..3 do
        {:ok, _} = db(:logs) |> insert(user_id: user.id, log: "entry #{n}") |> TestDb.run()
      end

      :ok
    end

    test "returns the number of rows deleted" do
      assert {:ok, %{deleted: 2}} = db(:logs) |> filter("id > $1", 1) |> delete() |> TestDb.run()
    end

    test "returns zero when nothing matches" do
      assert {:ok, %{deleted: 0}} =
               db(:logs) |> filter("id > $1", 100) |> delete() |> TestDb.run()
    end
  end
end
