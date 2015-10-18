defmodule MoebiusUpdateTest do
  use ExUnit.Case

  import Moebius.Commands

  setup_all do
    {:ok, cmd: %{email: "test@test.com"}, where: %{id: 1} |> update :users}
  end

  test "SQL is generated properly", %{cmd: cmd} do
    assert cmd.sql == "UPDATE users SET email=$1 RETURNING *;"
  end

  test "Params are set properly", %{cmd: cmd} do
    assert List.first(cmd.params) == "test@test.com"
  end

end
