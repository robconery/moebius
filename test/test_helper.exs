ExUnit.start()

defmodule TestDb do
  use Moebius.Database
end

Supervisor.start_link([TestDb], strategy: :one_for_one)
