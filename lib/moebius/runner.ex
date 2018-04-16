defmodule Moebius.Runner do
  require Logger

  @doc """
  Executes a command for a given transaction specified with `pid`. If the execution fails,
  it will be caught in `Query.transaction/1` and reported back using `{:error, err}`.
  """
  def execute(sql), do: execute(sql, [])
  def execute(sql, params) do
    
    #this will get routed through the Worker
    #which will end up calling execute/3, below
    :poolboy.transaction(
      :default,
      fn(pid) -> GenServer.call pid, %{sql: sql, params: params} end,
      :infinity
    )
  end

  def execute(pid, sql, params \\ []) do
    Logger.debug sql
    params = handle_nils(params)
    :epgsql.equery(pid, sql, params)
    |> handle_tx_result(pid)
  end

  #FIXME: THIS IS SUCH A HACK
  def handle_nils(params) do
    Enum.map params, fn(p) ->
      case p do
        nil -> :null
        p -> p
      end
    end
  end

  def handle_tx_result(res, pid) do
    case res do
      {:ok, [], []} -> {:ok, 0}
      {:ok, cols, rows} -> {:ok, cols, rows}
      {:ok, num} -> {:ok, num}
      {:ok, num, cols, rows} -> {:ok, cols, rows}
      {:error, { _, _, _, message, _}} -> {:error, message}
      {:error, { _, _, _, _, message, [detail: detail, file: _, line: _, position: _, routine: _, severity: _, where: _]}} -> {:error, "#{message}: #{detail}"}
      {:error, { _, _, _, _, message, _ }} -> {:error, message}
    end
  end

end
