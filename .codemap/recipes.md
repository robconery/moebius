# Recipes — task → exact files to touch

> The highest-leverage artifact. Each recipe short-circuits exploration.
> Pipeline shape: `db(:table) |> builder fns (build %QueryCommand{}/%DocumentCommand{}) |> TestDb.run()/first()/find()` → `Moebius.Database.execute` → `Moebius.Pool.checkout` → `Moebius.Connection.query` (parse → `Moebius.Params.check` → epgsql `prepared_query`) → `Moebius.Transformer`.
> Load the matching skill first: `postgres-sql` for builders/SQL, `erlang-otp` for pool/driver, `elixir-testing` for tests.

## Add a new relational query builder function (e.g. `having`)
1. `lib/moebius/query.ex` — add `def foo(%QueryCommand{} = cmd, ...)`; set fields on the struct or build `sql` directly (see `insert/2`, `update/2`, `delete/1`, `count/1`; SELECT sql is assembled in `select/2`). Every name goes through `Moebius.Identifier.name!/1`; every value goes in `cmd.params` as `$n`, numbered after `length(cmd.params)`
2. `lib/moebius/query_command.ex` — add a struct field if new state is needed
3. If it needs a new result shape: `lib/moebius/database.ex` — `shape/2` picks `to_single` or `to_list` by `cmd.type`
4. `test/moebius/<feature>_test.exs` — assert `cmd.sql` and `cmd.params`, plus a live `TestDb.run()`

## Add a new filter operator (e.g. `like:`)
1. `lib/moebius/query_filter.ex` — one clause of `filter/3`; build the predicate and `join_predicates/2` it (that handles first vs. appended conditions)
2. `test/moebius/query_filter_test.exs` (SQL) and `test/moebius/filter_test.exs` (round trip)

## Add/change document (JSONB) store behavior
1. `lib/moebius/document_query.ex` — builder fns (`contains`, `filter`, `search`, `insert`, `update`, `create_table_sql`, `update_search`). Document keys go through `Identifier.json_key/1`
2. `lib/moebius/document_command.ex` — struct (`json_field` defaults to "body")
3. `lib/moebius/database.ex` — `save_document/3`, `execute_document/2` (auto-creates a missing table once, on `:undefined_table`), `create_document_table/2` (advisory lock)
4. `test/moebius/document_test.exs`

## Support a new Postgres type (or change how one decodes)
1. `lib/moebius/codec/` — an `:epgsql_codec` module (`init/2`, `names/0`, `encode/3`, `decode/3`, `decode_text/3`); register it in `@codecs` in `lib/moebius/connection.ex`
2. `lib/moebius/params.ex` — add a `cast/2` clause so a wrong value is an error, not a connection crash
3. `test/moebius/types_test.exs` — round-trip it as a parameter and as a result, NULL included

## Change pool, checkout or transaction behavior
1. `lib/moebius/pool.ex` — `config/2` (pooler options), `checkout/2`, `transaction/2` (`run_open_block/4`), `stream/5`
2. `lib/moebius/connection.ex` — epgsql options (`epgsql_options/1`), `setup/2` (per-connection settings), the broken flag
3. `test/moebius/pool_test.exs` (start a small `TinyDb` pool there) and `test/moebius/transaction_test.exs`

## Change how results come back (maps, single row, JSON)
1. `lib/moebius/transformer.ex` — `to_list`, `to_single`, `from_json` (all take `{:ok, %Moebius.Result{}}` or `{:error, _}`)
2. `lib/moebius/database.ex` — which transformer each `run`/`first`/`find` clause pipes to

## Change connection/config handling
1. `lib/moebius.ex` — `get_connection/1`, `parse_connection/1` (URL → opts; explicit opts win)
2. `lib/moebius/connection.ex` — `epgsql_options/1`; document new options in the `Moebius.Database` moduledoc and README
3. `config/<env>.exs` — `:moebius, connection:`; `scripts:` dir for `sql_file`

## Add a mix task
1. `lib/mix/tasks/moebius.<name>.ex` — `use Mix.Task`, `run/1`; `Mix.Task.run("app.config")`, start `:epgsql`, reuse `Mix.Tasks.Moebius.Helpers`

## Add test schema/fixtures
1. `test/db/tables.sql` (schema) / `test/db/seeds.sql` (data); `test/db/*.sql` for `sql_file(:name)` tests
2. Run tests: `MIX_ENV=test mix moebius.migrate && MIX_ENV=test mix moebius.seed && mix test` (needs local Postgres, db `moebius_test`)
3. Tests reset what they read (`Moebius.TestData.reset_users!/0`); never depend on seed rows
