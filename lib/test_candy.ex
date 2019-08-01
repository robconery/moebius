defmodule TestCandy do
  @moduledoc false

  # only for testing document query.
  # We cannot get derive or defimpl to be available to
  # the modebius modules when running the tests if this
  # module is only in the test directory.

  defstruct id: nil,
            sticky: true,
            chocolate: :gooey

  defimpl Jason.Encoder, for: TestCandy do
    def encode(value, opts) do
      Jason.Encode.map(Map.take(value, [:id, :sticky, :chocolate]), opts)
    end
  end
end
