defmodule Mix.Tasks.Moebius.Drop do
  @moduledoc """
  Drops the database named in the `:connection` config
  """
  use Mix.Task

  alias Mix.Tasks.Moebius.Helpers

  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:epgsql)

    Moebius.get_connection() |> Helpers.drop_database()
  end
end
