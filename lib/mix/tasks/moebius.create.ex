defmodule Mix.Tasks.Moebius.Create do
  @moduledoc """
  Creates the database named in the `:connection` config
  """
  use Mix.Task

  alias Mix.Tasks.Moebius.Helpers

  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:epgsql)

    Moebius.get_connection() |> Helpers.create_database()
  end
end
