defmodule Moebius.Result do
  @moduledoc """
  The raw result of one statement, before Moebius turns rows into maps.

  `run_batch/1` and `transact_batch/1` return these, one per command.

  * `:command` - `:select`, `:insert`, `:update`, `:delete`, `:create` and so on.
  * `:columns` - column names, in order.
  * `:rows` - a list of rows, each a list of values in column order. `nil` for statements
    that don't return rows.
  * `:num_rows` - rows returned, or rows affected.
  """

  defstruct command: nil, columns: [], rows: nil, num_rows: 0

  @type t :: %__MODULE__{
          command: atom() | nil,
          columns: [String.t()],
          rows: [list()] | nil,
          num_rows: non_neg_integer()
        }
end
