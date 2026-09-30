# Recipes — task → exact files to touch

> The highest-leverage artifact. Each recipe short-circuits exploration.
> Pipeline shape: `db(:table) |> builder fns (build %QueryCommand{}/%DocumentCommand{}) |> TestDb.run()/first()/find()` → `Moebius.Database.execute` (Postgrex) → `Moebius.Transformer`.

## Add a new relational query builder function (e.g. `having`)
1. `lib/moebius/query.ex` — add `def foo(%QueryCommand{} = cmd, ...)`; set fields on the struct or build `sql` directly (see `insert/2`, `update/2`, `delete/1`, `count/1`; SELECT sql is assembled in `select/2`)
2. `lib/moebius/query_command.ex` — add struct field if new state is needed
3. If it needs a new result shape/type: `lib/moebius/database.ex` — add a `run/1` (and `run/2` with `%DBConnection{}`) clause matching `type:`
4. `test/moebius/<feature>_test.exs` — assert `cmd.sql` and a live `TestDb.run()`

## Add a new filter operator (e.g. `like:`)
1. `lib/moebius/query_filter.ex` — add clauses in BOTH groups: the `%{where: ""}` (first-condition) group and the general (append `and`) group
2. `test/moebius/query_filter_test.exs`

## Add/change document (JSONB) store behavior
1. `lib/moebius/document_query.ex` — builder fns (`contains`, `filter`, `search`, `insert`, `update`, ...)
2. `lib/moebius/document_command.ex` — struct (`json_field` defaults to "body")
3. `lib/moebius/database.ex` — `save/2`, `create_document_table` (auto-creates table on "does not exist"), `update_search`
4. `test/moebius/document_test.exs`

## Change how results come back (maps, single row, JSON)
1. `lib/moebius/transformer.ex` — `to_list`, `to_single`, `from_json`
2. `lib/moebius/database.ex` — which transformer each `run`/`first`/`find` clause pipes to

## Change connection/config handling
1. `lib/moebius.ex` — `get_connection/1`, `parse_connection/1` (URL → Postgrex opts), `pool_opts/0`
2. `config/<env>.exs` — `:moebius, connection:`; `scripts:` dir for `sql_file`

## Add a mix task
1. `lib/mix/tasks/moebius.<name>.ex` — `use Mix.Task`, `run/1`; reuse `Mix.Tasks.Moebius.Helpers`

## Add test schema/fixtures
1. `test/db/tables.sql` (schema) / `test/db/seeds.sql` (data); `test/db/*.sql` for `sql_file(:name)` tests
2. Run tests: `mix moebius.create && mix moebius.migrate && mix test` (needs local Postgres, db `moebius_test`)
