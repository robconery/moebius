# defmodule Subscriptions do
#
#   use Coyote.Controller, route: "/subscriptions", authenticate: true, roles: "Adminstrator"
#   use Moebius.Query
#   use TestDb
#
#   #/subscriptions/information
#   get :information, conn do #information.eex
#     db(:subscriptions)
#       |> find(conn.params["id"])
#       |> TestDb.run
#   end
#
#   #/subscriptions/?sort=year
#   get :index, conn do #template: index
#     db(:subscriptions)
#       |> find(conn.params["id"])
#       |> TestDb.run
#   end
#
#   #/subscriptions/johnny/current
#   get :show, conn do #template: "show.eex"
#     db(:subscriptions)
#       |> find(conn.params["id"])
#       |> TestDb.run
#   end
#
# end
#


defmodule Moebius do

  @doc """
  A convenience tool for assembling large queries with multiple commands. Not used
  currently. These functions hand off to PSQL because Postgrex can't run more than
  one command per query.
  """
  def run_with_psql(sql, opts) do
    db = opts[:database] || opts[:db]
    args = ["-d", db, "-c", sql, "--quiet", "--set", "ON_ERROR_STOP=1", "--no-psqlrc"]
    System.cmd "psql", args
  end

end
