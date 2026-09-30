# Moebius: Project Brief

**What it is.** Moebius is a small Elixir library (about 1,800 lines in `lib/`) for querying PostgreSQL in a functional, pipe-first style. It is not an ORM: there are no schemas, no migrations and no mapping. It builds SQL strings, runs them through epgsql (the Erlang Postgres driver) with a pooler connection pool, and returns plain maps. It has two ways to query:

1. **Relational**, `Moebius.Query`: `db(:users) |> filter(...) |> sort(...) |> limit(...)`, plus insert, update, delete, bulk_insert, join, count, group, reduce, full-text `search`, `sql_file` and `function`.
2. **Document store**, `Moebius.DocumentQuery`: stores maps in a `jsonb` column called `body`. It creates the table and GIN indexes the first time you save, and it can keep a `tsvector` column up to date for full-text search.

Status: v4.2.0 on Hex (2024-10-23). 5.0.0, the epgsql release, is on the `epgsql-driver` branch; see `CHANGELOG.md`. It is MIT-licensed; the maintainers are Rob Conery and Chase Pursley.

---

## How it works

```
db(:table)                     → %QueryCommand{table_name: "table"}     (or %DocumentCommand{})
  |> filter/sort/limit/...     → fills in the where/order/limit/params fields
  |> insert/update/delete/...  → writes cmd.sql itself and sets cmd.type
  |> MyDb.run | first | find   → (if sql is nil, select() builds the SELECT)
                               → Moebius.Database.execute → Pool.checkout → Connection.query
                                   (parse, check params against the parsed types, bind + execute)
                               → Moebius.Transformer.to_list | to_single | from_json → maps
```

- **Builders do no I/O.** Each one takes a struct and returns a new one, so you can check `cmd.sql` and `cmd.params` directly. Most tests do exactly that.
- **`use Moebius.Database`** (`database.ex`, a `__using__` macro) turns a module into a database with its own pooler pool, started as one supervisor child in the user's tree. It adds `run/1,2,3`, `first/1`, `find/2`, `save/2,3`, `transaction/1`, `rollback/1`, `stream/2`, `explain/2`, `copy/3`, `run_batch/1`, `transact_batch/1`, `pool_status/0` and `create_document_table/1,2`. `Moebius.Db` is the built-in module of this kind. Tests use `TestDb` (`test/support/`).
- **The driver layer** (all `@moduledoc false` except `Moebius.Connection`, `Moebius.Error` and `Moebius.Result`):
  - `pool.ex`: pooler config, checkout/return, transactions (savepoints when nested), cursor streams. A process that holds a connection reuses it for every query on the same pool, which is how plain `run/1` joins an open transaction.
  - `connection.ex`: epgsql connect options, `query/3` (parse → `Moebius.Params.check` → `prepared_query`), `script/2` for multi-statement SQL, and the "broken connection" flag that makes the pool replace a member.
  - `params.ex`: checks every parameter against the type Postgres parsed, because epgsql encodes inside the connection process and a wrong type would crash it.
  - `codec/`: epgsql codecs for date/time/timestamp(tz) (Elixir structs, exact microseconds), numeric (`Decimal`) and JSON (Jason).
  - `copy.ex`: `copy/3`, binary `COPY FROM STDIN` in chunks from any Enumerable.
  - `identifier.ex`: checks every table/column/function/file name before it goes into SQL.
- **Connection** settings come from `config :moebius, connection: [...]` (either a keyword list or `url:`) and go through `Moebius.get_connection/0`. Explicit options win over the parts of the url.
- **Transactions**: `MyDb.transaction(fn tx -> cmd |> MyDb.run(tx) end)`. A failed statement inside raises `Moebius.Error`; `Pool.transaction` rolls back and returns `{:error, message}`. Other exceptions roll back and are re-raised.
- **Mix tasks**: `moebius.create`, `moebius.drop`, `moebius.migrate` and `moebius.seed`, all through `Moebius.run_script/2` (epgsql's simple protocol runs multi-statement scripts; no `psql` needed). Migrate and seed only run in the test env. The aliases are `moebius.setup` and `moebius.reset`.

Navigation: `.codemap/MAP.md` lists what each directory holds, and `.codemap/recipes.md` lists which files to change for each kind of task.

---

## Current state (after phase 2, 2026-09-30)

Toolchain: Elixir 1.20.4 / OTP 29.0.5 (`.tool-versions`). Postgres 17.4 locally. `elixir: "~> 1.15"` is unchanged for library users.

| Check | Result |
|---|---|
| `mix compile --warnings-as-errors` | ✅ clean in dev and test |
| `mix test` | ✅ **209 passed** (9 doctests), no log noise; stable over 25+ runs with random seeds |
| `mix quality --strict` | ✅ format, sobelow (0 findings, fails on any), credo all clean |
| `mix hex.audit` | ✅ no advisories |

| Runtime dep | Locked | Note |
|---|---|---|
| epgsql | 4.8.0 | no deps |
| pooler | 1.7.0 | no deps |
| jason | 1.4.5 | |
| decimal | 3.1.1 | CVE-2026-32686 fixed |

See `plan.md` for the phase 1 and phase 2 task logs.

---

## Known limits (not bugs, but worth knowing)

- Column names and document keys become atoms (`String.to_atom`). That's the public API, and it's safe only because they are a bounded set. Documented in `Moebius.Transformer`.
- `search/2` uses `to_tsquery`, which raises a syntax error on ordinary user input ("red shoes"). `websearch_to_tsquery` would be kinder; changing it changes search semantics, so it's left for a later release.
- `bulk_insert` (multi-row `VALUES`) is about 22% slower than on Postgrex, because epgsql copies each 20,000-parameter message to the connection process. `copy/3` is the fast path (4.6x faster than 4.x's bulk_insert).
- Under heavy concurrency (50 processes on a 10-connection pool) throughput is about 11% below Postgrex: epgsql encodes and decodes in the connection process. Single queries are 5-17% faster.
- LISTEN/NOTIFY isn't exposed. epgsql supports it through a dedicated connection.
- The public builder API has no typespecs yet.

---

## Upgrade plan

**Phase 1: build on current tooling.** ✅ Done (see `plan.md`).

**Phase 2: replace Postgrex with epgsql + pooler, fix the known defects.** ✅ Done on `epgsql-driver` (see `plan.md` and `CHANGELOG.md`).

**Next**
1. Release 5.0.0: tag `v5.0.0` (ex_doc `source_ref` depends on it) and `mix hex.publish`.
2. Pick from the known limits above: `websearch_to_tsquery`, LISTEN/NOTIFY, typespecs, an opt-in prepared-statement cache (one round-trip per repeated query instead of two).

Verify with `MIX_ENV=test mix moebius.migrate && MIX_ENV=test mix moebius.seed && mix test && mix quality --strict`.
