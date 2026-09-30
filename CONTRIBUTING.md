# Contributing to Moebius

Thanks for wanting to help! Bug reports, fixes, docs and ideas are all welcome.

## Getting set up

You need Elixir 1.15 or later and a local PostgreSQL (the suite runs on 17). The test config expects `postgres:postgres@localhost:5432` and a database called `moebius_test`; see `config/test.exs`.

```sh
git clone https://github.com/robconery/moebius
cd moebius
mix deps.get
MIX_ENV=test mix moebius.setup   # creates moebius_test, loads test/db/tables.sql and seeds.sql
mix test
```

If you use asdf or mise, `.tool-versions` has the Elixir and OTP versions CI runs on.

## Before you open a pull request

CI runs these, so it's quicker to run them first:

```sh
mix compile --warnings-as-errors
mix test
mix test --repeat-until-failure 10   # catches tests that depend on order or timing
mix quality --strict                 # format check, sobelow and credo
```

## What a good pull request looks like

- **A bug fix comes with a test** that fails without the fix and passes with it. That's the one hard rule.
- **Every test owns its data.** Create the rows your test checks in the test (or its `setup`), and assert exact values, not just "something came back". `Moebius.TestData.reset_users!/0` resets the shared tables.
- **Values are parameters, names are checked.** Anything that goes into SQL as a value must be a `$n` parameter. Table, column and function names go through `Moebius.Identifier`. If you add a new parameter type, cover it in `Moebius.Params`, because a wrong-typed parameter crashes an epgsql connection process.
- **Builders don't do I/O.** Functions in `Moebius.Query` and `Moebius.DocumentQuery` return a struct; only the database module runs anything.
- Keep pull requests small and focused. A short description of the problem and the fix is plenty.
- Update `CHANGELOG.md` under an "Unreleased" heading if users will notice the change.

## Finding your way around

`PROJECT.md` explains how a query travels from `db(:users)` to a list of maps. `.codemap/MAP.md` lists what each file holds, and `.codemap/recipes.md` answers "where do I add X?".

The core modules, all in `lib/moebius/`:

| File | What it does |
|---|---|
| `query.ex`, `query_filter.ex` | the relational builder and its where clauses |
| `document_query.ex` | the JSONB document builder |
| `database.ex` | `use Moebius.Database`: run, first, find, save, transaction, stream, explain, copy |
| `pool.ex`, `connection.ex`, `copy.ex`, `params.ex`, `codec/` | the driver layer on epgsql and pooler |
| `identifier.ex` | checks every name that goes into SQL |
| `transformer.ex` | turns results into maps |

## Working with an AI assistant

`.claude/skills/` holds the rules the 5.0 code was written against: `erlang-otp` (processes, the pool, calling epgsql and pooler), `postgres-sql` (how Moebius builds SQL), `elixir-testing` (test isolation and style) and `supabase-postgres-best-practices`. Claude Code picks them up automatically, and they're plain Markdown, so they're worth a read either way. AI-assisted pull requests are fine; you're still the one responsible for what's in them, so please read and test your change before you send it.

## Reporting bugs

Open an issue with the smallest query that shows the problem, what you expected, and what happened (the full error helps). Your Elixir, OTP, Postgres and Moebius versions help too.

For security problems, please don't open a public issue. See [SECURITY.md](SECURITY.md).

## Code of conduct

Be kind. Everyone here is volunteering their time. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
