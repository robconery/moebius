# Code Map

> Read this FIRST. Directory → purpose. Drill into an area only when needed.
> Fill `TODO` purposes via a single batched pass; they survive rebuilds.

- `.` (7 files: 3·, 2.exs, 1.md) — mix.exs (deps, version), README (full API docs by example), .formatter.exs, .tool-versions
- `.github/workflows` (1 files: 1.yml) — CI: GitHub Actions, Postgres service, `mix test` under MIX_ENV=test
- `config` (3 files: 3.exs) — config.exs imports <env>.exs; test.exs sets `:moebius, connection: [url: ...]` and `scripts: "test/db"` (sql_file dir)
- `lib` (1 files: 1.ex) — moebius.ex — OTP app entry, connection parsing (`get_connection`, `parse_connection` URL→opts), `run_with_psql`, `pool_opts`
- `lib/mix/tasks` (5 files: 5.ex) — Mix tasks: moebius.create / drop / migrate (runs test/db/tables.sql, test env only) / seed; helpers.ex shells out to `psql -U postgres -c "CREATE/DROP DATABASE ..."`
- `lib/moebius` (10 files: 10.ex) — Core library. query.ex = relational query builder (pipes into %QueryCommand{}, builds SQL); query_filter.ex = where-clause builder (eq/gt/in/...); document_query.ex = JSONB document-store builder (%DocumentCommand{}); database.ex = `use Moebius.Database` macro giving run/first/find/save/transaction + raw Postgrex execute; transformer.ex = Postgrex result → maps/lists/JSON; *_command.ex/command_batch.ex = structs; postgrex_types.ex = Jason JSON types
- `test` (1 files: 1.exs) — test_helper.exs defines `TestDb` (`use Moebius.Database`) and starts it — tests call `|> TestDb.run()`
- `test/db` (4 files: 4.sql) — SQL fixtures: tables.sql (schema, used by migrate), seeds.sql, and sql_file() scripts (simple.sql, cte.sql)
- `test/moebius` (17 files: 17.exs) — ExUnit tests, one file per feature (insert, update, delete, join, document, full_text_search, transaction, bulk_insert, ...). Most assert both generated `cmd.sql` and live DB result
