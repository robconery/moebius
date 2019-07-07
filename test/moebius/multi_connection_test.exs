# defmodule DB1, do: use Moebius.Database
# defmodule DB2, do: use Moebius.Database
#
#
# defmodule Moebius.BasicSelectTest do
#
#   use ExUnit.Case
#   import Moebius.Query
#
#   setup_all do
#     children = [
#       {DB1, [Moebius.get_connection(:test_db)]}
#       {DB2, [Moebius.get_connection(:chinook)]}
#     ]
#     Supervisor.start_link children, strategy: :one_for_one
#
#     {:ok, [thing: true]}
#   end
#
#   test "they connect to different dbs" do
#     {:ok, res} = db(:artist) |> limit(1) |> DB2.run
#     IO.inspect res
#   end
#
# end
