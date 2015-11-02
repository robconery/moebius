defmodule Moebius.ConnectionReleaseTest do
  use ExUnit.Case
  #import Moebius.Query

  # setup do
  #   "delete from users cascade;" |> Moebius.Query.run
  #   "delete from people"
  #     |> Moebius.Query.run
  #   {:ok, res: true}
  # end

  # test "loading 100 at once" do
  #   res = write_benchmark(100)
  #   IO.puts "Finished"
  # end
  #
  # test "loading 1000 at once" do
  #   res = write_benchmark(1000)
  #   IO.puts "Finished"
  # end

  # test "50K inserts with psql" do
  #   cmds = user_pulls(10_000_000)
  #   sql = Enum.join(cmds, ";")
  #   res = Moebius.Runner.run_with_psql(sql, "meebuss")
  #   IO.inspect res
  # end

  # test "fifty thousand writes" do
  #   "delete from users cascade;" |> Moebius.Query.run
  #   cmds = user_writes(50000)
  #   sql = Enum.join(cmds, ";\r\n")
  #   file = write_batch_to_file(sql)
  #   #res = System.cmd "psql", "-d", "meebuss", "-f", "db.sql"
  #   #IO.inspect sql
  #   res = Moebius.Runner.run_file_with_psql(file, "meebuss")
  #   IO.inspect res
  # end

  # test "50K concurrent writes" do
  #   Enum.map(1..200, fn(n) ->
  #     sql="insert into users(first, last email) values($1, $2, $3);"
  #     user = [email: "test#{n}@test.com", first: "First #{n}", last: "Last #{n}"]
  #     cmd = %Moebius.QueryCommand{table_name: "users" }
  #     res = spawn(Moebius.Query, :insert, [cmd, user])
  #     end
  #   )
  #   IO.puts "Done"
  # end

  # def user_write_commands(qty) do
  #   Enum.map(1..qty, fn(n) ->
  #       db(:users)
  #         |> insert(email: "test#{n}@test.com", first: "First #{n}", last: "Last #{n}")
  #     end
  #   )
  # end
  #
  # def user_write_sql(qty) do
  #   Enum.map(1..qty, fn(n) ->
  #       "insert into users(first, last, email) values('first #{n}', 'last #{n}', 'test#{n}@test.com')"
  #     end
  #   )
  # end
  #
  # def user_pulls(qty) do
  #   Enum.map(1..qty, fn(n) ->
  #       "select * from users where id= 1"
  #     end
  #   )
  # end
  #
  # def write_batch_to_file(sql_blob) do
  #   build_file = "db.sql"
  #   {:ok, file} = File.open build_file, [:write]
  #   IO.binwrite file, sql_blob
  #   File.close file
  #   build_file
  # end

  # def people(qty) do
  #   Enum.map(1..qty, &(
  #     [
  #       first_name: "FirstName #{&1}",
  #       last_name: "LastName #{&1}",
  #       address: "666 SW Pine St.",
  #       city: "Portland",
  #       state: "OR",
  #       zip: "97209" ]))
  # end
  #
  # def write_benchmark(qty) do
  #   people(qty)
  #   |> Enum.map(fn(p) ->
  #     db(:people)
  #       |> save(p)
  #   end)
  # end
end
