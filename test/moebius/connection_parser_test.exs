defmodule ConnectionParserTest do
  use ExUnit.Case

  test "It parses a URL" do
    res = "postgres://rob@localhost/redfour"
      |> Moebius.Runner.parse_connection_args

    assert res.database == "redfour"
  end

  test "parses a normal list of stuff" do
    res = [database: "redfour", username: "rob"]
      |> Moebius.Runner.parse_connection_args
    assert res.database == "redfour"
  end
end
