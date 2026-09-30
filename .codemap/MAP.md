# Code Map

> Read this FIRST. Directory → purpose. Drill into an area only when needed.
> Fill `TODO` purposes via a single batched pass; they survive rebuilds.

- `.` (11 files: 4.md, 3·, 2.exs) — mix.exs (deps, version), README (full API docs by example), .formatter.exs, .tool-versions
- `.claude/skills/elixir-testing` (1 files: 1.md) — Skill: ExUnit standards for this suite (data isolation on a shared DB, assertion style, flake checks)
- `.claude/skills/erlang-otp` (3 files: 3.md) — Skill: OTP rules for a library on epgsql + pooler; references/epgsql.md and references/pooler.md document both APIs as used here
- `.claude/skills/postgres-sql` (1 files: 1.md) — Skill: how the builders must write SQL (params, identifier checks, index-friendly SQL, pagination, bulk writes, transactions)
- `.claude/skills/supabase-postgres-best-practices` (36 files: 36.md) — Skill (third-party, supabase/agent-skills): general Postgres rules; references/<category>-<rule>.md
- `.github/workflows` (1 files: 1.yml) — CI: GitHub Actions, Postgres service, `mix test` under MIX_ENV=test
- `config` (4 files: 4.exs) — config.exs imports <env>.exs; test.exs sets `:moebius, connection: [url: ...]` and `scripts: "test/db"` (sql_file dir)
- `lib` (1 files: 1.ex) — moebius.ex — `Moebius` (get_connection, parse_connection URL→opts, run_script/2 for multi-statement SQL) and the ready-made `Moebius.Db`
- `lib/mix/tasks` (5 files: 5.ex) — Mix tasks: moebius.create / drop / migrate (test/db/tables.sql) / seed (seeds.sql); helpers.ex runs them through Moebius.run_script (epgsql, no psql)
- `lib/moebius` (8 files: 8.ex) — Core library. Builders: query.ex (%QueryCommand{}), query_filter.ex (where clauses), document_query.ex (JSONB, %DocumentCommand{}), identifier.ex (name checks). Running: database.ex (`use Moebius.Database` macro), pool.ex (pooler checkout, transactions/savepoints, cursor streams), connection.ex (epgsql calls), params.ex (param type checks), transformer.ex (%Moebius.Result{} → maps). error.ex, result.ex, *_command.ex = structs
- `lib/moebius/codec` (3 files: 3.ex) — epgsql codecs: date_time.ex (date/time/timestamp(tz) ↔ Elixir structs, exact µs), numeric.ex (↔ Decimal), json.ex (Jason adapter)
- `test` (1 files: 1.exs) — test_helper.exs starts `TestDb` under a supervisor
- `test/db` (4 files: 4.sql) — SQL fixtures: tables.sql (schema, used by migrate), seeds.sql, and sql_file() scripts (simple.sql, cte.sql)
- `test/moebius` (16 files: 16.exs) — ExUnit tests, one file per feature. Builder tests assert `cmd.sql`/`cmd.params`; round-trip tests run through TestDb. types_test (codecs), pool_test (failures, timeouts, second pools), security_test (injection), stream_test, explain_test
- `test/support` (2 files: 2.ex) — TestDb (`use Moebius.Database`) and Moebius.TestData (reset_users!/0, unique_email/1); compiled in the test env only
