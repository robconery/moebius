ExUnit.start()
defmodule TestDb,  do: use Moebius.Database
import Moebius.Query

worker = Supervisor.Spec.worker(TestDb, url: "postgresql://rob@localhost/meebuss")
Supervisor.start_link [worker], strategy: :one_for_one

IO.inspect "Dropping and reloading db..."
sql_file(:test_schema) |> TestDb.first
IO.inspect "Here we go..."

