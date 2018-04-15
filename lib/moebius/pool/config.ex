defmodule Moebius.Pool.Config do
  @doc """
  Return value by key from config.exs file.
  """
  def get(name, default \\ nil) do
    Application.get_env(:moebius_pool, name, default)
  end
end