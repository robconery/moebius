defmodule Moebius.TestData do
  @moduledoc false
  # Shared setup for tests that touch the database. Every test owns its rows,
  # so each module resets the tables it reads before each test.

  @doc "Empties users and logs and restarts their id sequences."
  def reset_users! do
    {:ok, []} = TestDb.run("truncate users, logs restart identity cascade")
    :ok
  end

  @doc "An email address no other test is using."
  def unique_email(prefix \\ "user"),
    do: "#{prefix}-#{System.unique_integer([:positive])}@test.com"
end
