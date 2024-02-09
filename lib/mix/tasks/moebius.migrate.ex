defmodule Mix.Tasks.Moebius.Migrate do
  @moduledoc """
  Migrates the database
  """
  use Mix.Task

  def run(_args) do
    IO.inspect("Migrating database")
    Mix.Task.run("app.start")

    Moebius.get_connection()
    |> IO.inspect()
    |> migrate_database()
    |> IO.inspect()
  end

  defp migrate_database(opts) do
    case Mix.env() do
      :test ->
        "test/db/tables.sql"
        |> File.read!()
        |> IO.inspect()
        |> Moebius.run_with_psql(opts)
        |> IO.inspect()

      _ ->
        raise "You can only run migrations in the test environment"
    end
  end
end
