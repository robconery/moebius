defmodule Mix.Tasks.Moebius.Helpers do
  @moduledoc false

  # CREATE DATABASE can't run inside the database it creates, so connect to the
  # `postgres` maintenance database with the same credentials.
  def create_database(opts) do
    name = Moebius.Identifier.name!(opts[:database])
    maintenance(opts, "create database #{name}")
  end

  def drop_database(opts) do
    name = Moebius.Identifier.name!(opts[:database])
    maintenance(opts, "drop database if exists #{name}")
  end

  def run_file(opts, path) do
    path |> File.read!() |> Moebius.run_script(opts) |> report()
  end

  defp maintenance(opts, sql) do
    opts |> Keyword.put(:database, "postgres") |> then(&Moebius.run_script(sql, &1)) |> report()
  end

  defp report(:ok), do: :ok
  defp report({:error, message}), do: Mix.raise(message)
end
