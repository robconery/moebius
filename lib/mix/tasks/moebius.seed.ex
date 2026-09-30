defmodule Mix.Tasks.Moebius.Seed do
  @moduledoc """
  Loads the test data in `test/db/seeds.sql`. Test environment only.
  """
  use Mix.Task

  alias Mix.Tasks.Moebius.Helpers

  def run(_args) do
    if Mix.env() != :test, do: Mix.raise("mix moebius.seed only runs in the test environment")

    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:epgsql)

    Moebius.get_connection() |> Helpers.run_file("test/db/seeds.sql")
  end
end
