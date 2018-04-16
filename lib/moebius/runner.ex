defmodule Moebius.Runner do
  
  def execute(sql) do
    {:ok, pid} = Moebius.connect()
    {:ok, cols, rows} = :epgsql.squery(pid, sql)
    {:ok, cols, rows, pid}
  end

  def execute(sql, params) do
    {:ok, pid} = Moebius.connect()
    {:ok, cols, rows} = :epgsql.equery(pid, sql, params)
    {:ok, cols, rows, pid}
  end

end