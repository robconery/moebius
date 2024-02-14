defmodule Mix.Tasks.Moebius.Drop do
  @moduledoc """
  Drops the database
  """
  use Mix.Task

  alias Mix.Tasks.Moebius.Helpers

  def run(_args) do
    Mix.Task.run("app.start")

    Moebius.get_connection()
    |> Keyword.get(:database)
    |> Helpers.drop_database()
  end
end
