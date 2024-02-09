defmodule Mix.Tasks.Moebius.Seed do
  @moduledoc """
  Seeds the database
  """
  use Mix.Task

  def run(_args) do
    Mix.Task.run("app.start")

    Moebius.get_connection()
    |> seed_database()
  end

  defp seed_database(opts) do
    case Mix.env() do
      :test ->
        "test/db/seeds.sql"
        |> File.read!()
        |> Moebius.run_with_psql(opts)

      _ ->
        raise "You can only run seeds in the test environment"
    end
  end
end
