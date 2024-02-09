defmodule Mix.Tasks.Moebius.Migrate do
  @moduledoc """
  Migrates the database
  """
  use Mix.Task

  def run(_args) do
    Mix.Task.run("app.start")

    Moebius.get_connection()
    |> migrate_database()
  end

  defp migrate_database(opts) do
    case Mix.env() do
      :test ->
        "test/db/tables.sql"
        |> File.read!()
        |> Moebius.run_with_psql(opts)

      _ ->
        raise "You can only run migrations in the test environment"
    end
  end
end
