types = Application.get_env(:moebius, :types)

if types == nil do
  Postgrex.Types.define(PostgresTypes, [], json: Jason)
else
  types
end
