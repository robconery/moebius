defmodule Moebius do
  use Application

  def start,  do: start(:normal, [])
  def start(_type, _args) do
    Moebius.Supervisor.start_link(_type, _args)
  end
end
