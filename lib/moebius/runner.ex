defmodule Moebius.Runner do
  
  def query(pid, sql) do
    # {:ok, pid} = Moebius.connect()
    # just use equery for everything I think...we could check for params, but squery uses the simple query protocol, 
    # which is limited usefulness, and queries with no params work fine with the extended protocol.
    {:ok, cols, rows} = :epgsql.squery(pid, sql)
    {:ok, cols, rows}
  end

  # def query(pid, sql, params) do
  #   # {:ok, pid} = Moebius.connect()
  #   # just use equery for everything I think...we could check for params, but squery uses the simple query protocol, 
  #   # which is limited usefulness, and queries with no params work fine with the extended protocol.
  #   {:ok, cols, rows} = :epgsql.equery(pid, sql, params)
  #   {:ok, cols, rows}
  # end

end