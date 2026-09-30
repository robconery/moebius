defmodule Moebius.Codec.JSON do
  @moduledoc false
  # The JSON module epgsql's json/jsonb codec calls (`{:epgsql_codec_json, Moebius.Codec.JSON}`).
  # epgsql wants iodata back from encode/1, which Jason.encode/1 doesn't give.
  # Decoded JSON has string keys. Documents are read as `body::text` and decoded with atom
  # keys by Moebius.Transformer instead.

  # Moebius.Params encodes JSON parameters before they reach the connection process
  def encode({:moebius_json, json}), do: json
  def encode(term), do: Jason.encode_to_iodata!(term)
  def decode(json), do: Jason.decode!(json)
end
