defmodule Mix.Tasks.Moebius.Create do
  @moduledoc """
  Creates the database
  """
  use Mix.Task

  alias Mix.Tasks.Helpers

  def run(_args) do
    IO.inspect("Creating database")
    Mix.Task.run("app.start")

    Moebius.get_connection()
    |> IO.inspect()
    |> Keyword.get(:database)
    |> create_database()
    |> IO.inspect()
  end

  defp create_database(database) do
    Helpers.create_database(database)
  end
end
