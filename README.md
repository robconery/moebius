# Moebius 4.0: A functional query tool for Elixir and PostgreSQL.
For the dumbest, most basic example...
to run silly tests for getting started. Will output log entries and `pid`s from consuming and using the connection pool
''' rb
$ mix test 
'''

OR

''' rb
$ iex -S mix
iex(1)> Moebius.query("select * from users")

# 10:17:36.227 [debug] [Connector] new connection to postgres pid #PID<0.226.0>...
# {:ok,
#  [
#    {27, "friend@test.com", :null, :null, 10, :null, :null},
#    {28, "enemy@test.com", :null, :null, 10, :null, :null},
#    {29, "aggs@test.com", "Rob", "Blah", 10, :null, :null},
#    {30, "boogerbob@test.com", "Mike", "Booger", 10, :null, :null}
#  ]}

'''

