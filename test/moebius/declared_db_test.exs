
defmodule DeclaredDbTest do
  use ExUnit.Case
  import TestDb


  test "simple SQL" do
    # Postgrex.start_link(name: __MODULE__, database: "meebuss")
    #Postgrex.query(__MODULE__, "select id from users", [])
    res = "select id from users" |> run([])
    IO.inspect res
  end
end
