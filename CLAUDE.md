# Moebius

Functional query library for Elixir + PostgreSQL. **Not an ORM**: no schemas, no mappings, no migrations. You pipe small functions to build a SQL command struct, then hand it to a database module to run through epgsql, the Erlang driver, with a pooler pool. Published on Hex as `moebius` (v4.2.0; 5.0.0 is the epgsql release, see `CHANGELOG.md`). See `PROJECT.md` for the full explanation.

```elixir
import Moebius.Query
db(:users) |> filter(email: "a@b.com") |> Moebius.Db.first()          # relational
import Moebius.DocumentQuery
db(:orders) |> contains(status: "open") |> Moebius.Db.run()            # JSONB document store
```

## Navigating the code

A codemap is in `.codemap/`. **Read `.codemap/MAP.md` first**, and use `recipes.md` for "where do I add X" questions and `glossary.md` for project terms. Grep `symbols.tsv` (`grep -P "^name\t" .codemap/symbols.tsv`) to find a definition; don't read it whole. Check that the map is current with `python3 ~/.claude/skills/codemap/scripts/index.py status --root .` and run `refresh` after changing code.

Core modules (all in `lib/moebius/`):
- `query.ex`: relational builder → `%QueryCommand{}`
- `query_filter.ex`: where clauses
- `document_query.ex`: JSONB builder → `%DocumentCommand{}`
- `database.ex`: `use Moebius.Database` macro (run/first/find/save/transaction/stream/explain) plus `execute`
- `pool.ex`, `connection.ex`, `params.ex`, `codec/`: the driver layer (pooler checkout, transactions, epgsql calls, parameter checks, type codecs)
- `identifier.ex`: checks every name that goes into SQL
- `transformer.ex`: turns `%Moebius.Result{}` into maps

## Skills (in `.claude/skills/`)

Load the matching skill before you change code:
- `erlang-otp`: processes, supervision, the pool, calling Erlang (epgsql, pooler). Its `references/` document the epgsql and pooler APIs.
- `postgres-sql`: any function that builds SQL, DDL, indexes, pagination, bulk writes, transactions.
- `supabase-postgres-best-practices`: general Postgres rules with examples (installed from supabase/agent-skills; update with `npx skills update`).
- `elixir-testing`: anything under `test/`. Every test owns its data. Check for flaky tests with `mix test --repeat-until-failure 20`.

## Running tests

Tests need a local Postgres with a `moebius_test` database, reachable as `postgres:postgres@localhost:5432` (see `config/test.exs`).

```sh
mix deps.get
MIX_ENV=test mix moebius.migrate   # loads test/db/tables.sql (drops and recreates tables)
MIX_ENV=test mix moebius.seed      # loads test/db/seeds.sql
mix test
mix quality                        # format check + sobelow + credo
```

Tests check the generated `cmd.sql` string and also run it against the database through `TestDb` (defined in `test/support/test_db.ex`). `Moebius.TestData.reset_users!/0` resets the shared tables.

## Conventions and gotchas

- Builders return a struct. Nothing touches the database until `Db.run/first/find/save`.
- Document tables are created automatically the first time you save to one (`id`, `body jsonb`, `search tsvector`, timestamps).
- Values go in as parameters, and names go through `Moebius.Identifier`. Never interpolate anything else into SQL.
- A wrong-typed parameter crashes an epgsql connection process. That's why `Moebius.Params` checks every parameter first; keep new types covered there.
- CI compiles with `--warnings-as-errors`, runs the suite, then `mix test --repeat-until-failure 10`.
- Current plan and task log: `plan.md`.
