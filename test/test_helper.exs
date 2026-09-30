ExUnit.start()

Supervisor.start_link([TestDb], strategy: :one_for_one)
