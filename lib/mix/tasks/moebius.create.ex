defmodule Mix.Tasks.Moebius.Create do
  @moduledoc """
  Creates the database
  """
  use Mix.Task

  alias Mix.Tasks.Moebius.Helpers

  def run(_args) do
    Mix.Task.run("app.start")

    Moebius.get_connection()
    |> Keyword.get(:database)
    |> Helpers.create_database()
  end
end
