defmodule Mix.Tasks.Moebius.Migrate do
  @moduledoc """
  Rebuilds the test database's tables from `test/db/tables.sql`. Test environment only.
  """
  use Mix.Task

  alias Mix.Tasks.Moebius.Helpers

  def run(_args) do
    if Mix.env() != :test, do: Mix.raise("mix moebius.migrate only runs in the test environment")

    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:epgsql)

    Moebius.get_connection() |> Helpers.run_file("test/db/tables.sql")
  end
end
