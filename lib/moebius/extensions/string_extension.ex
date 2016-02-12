defmodule Moebius.Extensions.StringExtension do
  @behaviour Postgrex.Extension

  def init(_, _), do: nil

  def matching(_), do: [
    type: "tsvector",
    type: "tsquery",
    type: "xml",
    type: "uuid",
    type: "money",
    type: "inet",
    # type: "timestamptz",
    # type: "time",
    # type: "date"

  ]

  def format(_), do: :text

  def encode(_, text, _, _) when is_binary(text) do
    text
  end

  def decode(_, text, _, _) do
    text
  end
end
