defmodule Moebius.Transaction  do
  use GenServer

  defstruct [
    creds: nil,
    pid: nil,
    cmd: nil,
    result: nil
  ]
  def start_link(creds) do
    #TODO: Demand a name here?
    GenServer.start_link(__MODULE__,[%Moebius.Transaction{creds: creds}])
  end

  def begin(pid, table) do
    Genserver.call pid,{:begin, table}
  end

  def commit(pid, cmd) do
    res = GenServer.call pid, {:commit, cmd}
    GenServer.cast pid, :stop
    res
  end
  
  def terminate(reason, state) do
    Postgrex.Connection.stop state.pid 
  end

  def handle_call({:begin, table}, _sender, tx) do
    cmd = %Moebius.QueryCommand{table_name: table}
    {:reply, cmd}
  end

  def handle_call({:commit, cmd}, _sender, tx) do
    {:ok, pid} = Postgrex.Connection.start_link tx.creds
    Postgrex.Connection.query tx.pid, "BEGIN"
    result = Postgrex.Connection.query(tx.pid, cmd.sql, cmd.args)
    case result do
      {:error, err} -> Postgrex.Connection.query(tx.pid, "ROLLBACK", []) && {:reply, err}
      {:ok, res} -> Postgrex.Connection.query(tx.pid, "COMMIT", []) && {:reply, transform(res)} 
    end
  end

  defp transform({:error, %Postgrex.Error{postgres: %{message: message}}}) do
    {:error, message}
  end

  defp transform({:ok, %Postgrex.Result{rows: rows, columns: cols}}) do
    for row <- rows, cols = atomize_columns(cols), do:
        match_columns_to_row(cols,row) |> to_map
  end

  defp atomize_columns(cols), do: for col <- cols, do: String.to_atom(col)
  defp match_columns_to_row(cols, row), do: List.zip([cols, row])
  defp to_map(list), do: Enum.into(list,%{})
end
