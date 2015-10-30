defmodule Moebius.TransformerTest do
  use ExUnit.Case

  import Moebius.Transformer

  test "convert list to map with atomized keys" do
    assert %{key: "value"} = to_map([{"key", "value"}])
    assert %{key: [%{key2: "value"}]} = to_map([{"key", [{"key2", "value"}]}])
  end
end
