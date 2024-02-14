defmodule Mix.Tasks.Moebius.Helpers do
  @moduledoc false
  def create_database(database_name) do
    "-c \"CREATE DATABASE #{database_name};\""
    |> database_cmd()
  end

  def drop_database(database_name) do
    "-c \"DROP DATABASE #{database_name};\""
    |> database_cmd()
  end

  defp database_cmd(cmd) do
    db_cmd = "psql -U postgres " <> cmd

    case System.shell(db_cmd) do
      {output, 0} ->
        output

      {output, _status} ->
        output
    end
  end
end
