defmodule Moebius do
  use Application

  def start,  do: start(:normal, [])
  def start(type, args) do
    Moebius.Supervisor.start_link(type, args)
  end

end
