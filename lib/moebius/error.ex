defmodule Moebius.Error do
  @moduledoc """
  An error from Postgres, the driver or the pool.

  Moebius's functions return `{:error, message}` with the message string, as they always
  have. Inside a transaction a failed statement raises this exception, and `transaction/1`
  turns it back into `{:error, message}` after rolling back.

  * `:code` - the SQLSTATE, e.g. `"23505"`. `nil` when the error didn't come from Postgres.
  * `:name` - the SQLSTATE as an atom, e.g. `:unique_violation`, or a Moebius reason such as
    `:pool_timeout`, `:connection_lost` or `:bad_parameter`.
  * `:message` - the primary message, as Postgres wrote it.
  * `:detail`, `:hint`, `:constraint`, `:table`, `:column` - extra fields Postgres sends when
    it has them.
  """

  defexception code: nil,
               name: nil,
               message: nil,
               detail: nil,
               hint: nil,
               constraint: nil,
               table: nil,
               column: nil

  @type t :: %__MODULE__{
          code: String.t() | nil,
          name: atom() | nil,
          message: String.t(),
          detail: String.t() | nil,
          hint: String.t() | nil,
          constraint: String.t() | nil,
          table: String.t() | nil,
          column: String.t() | nil
        }

  require Record

  Record.defrecordp(
    :pg_error,
    :error,
    Record.extract(:error, from_lib: "epgsql/include/epgsql.hrl")
  )

  @doc false
  def from_epgsql(pg_error(code: code, codename: name, message: message, extra: extra)) do
    %__MODULE__{
      code: code,
      name: name,
      message: message,
      detail: extra[:detail],
      hint: extra[:hint],
      constraint: extra[:constraint_name],
      table: extra[:table_name],
      column: extra[:column_name]
    }
  end

  def from_epgsql(:closed), do: %__MODULE__{name: :connection_lost, message: "connection closed"}
  def from_epgsql(:timeout), do: %__MODULE__{name: :timeout, message: "timeout"}

  def from_epgsql(:sync_required),
    do: %__MODULE__{name: :connection_lost, message: "connection needs a sync"}

  def from_epgsql(other), do: %__MODULE__{name: :driver_error, message: inspect(other)}
end
