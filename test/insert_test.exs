defmodule MoebiusInsertTest do
  use ExUnit.Case

  import Moebius.Commands

  # setup_all do
  #   {:ok, cmd: %{email: "test@test.com"} |> insert :users}
  # end
  #
  # test "SQL is generated properly", %{cmd: cmd} do
  #   assert cmd.sql == "INSERT INTO users(email) VALUES($1) RETURNING *;"
  # end
  #
  # test "Params are set properly", %{cmd: cmd} do
  #   assert List.first(cmd.params) == "test@test.com"
  # end

end
