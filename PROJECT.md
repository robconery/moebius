# Moebius: Project Brief

**What it is.** Moebius is a small Elixir library (about 1,800 lines in `lib/`) for querying PostgreSQL in a functional, pipe-first style. It is not an ORM: there are no schemas, no migrations and no mapping. It builds SQL strings, runs them through Postgrex and returns plain maps. It has two ways to query:

1. **Relational**, `Moebius.Query`: `db(:users) |> filter(...) |> sort(...) |> limit(...)`, plus insert, update, delete, bulk_insert, join, count, group, reduce, full-text `search`, `sql_file` and `function`.
2. **Document store**, `Moebius.DocumentQuery`: stores maps in a `jsonb` column called `body`. It creates the table and GIN indexes the first time you save, and it can keep a `tsvector` column up to date for full-text search.

Status: v4.2.0 on Hex, last released 2024-10-23. It is MIT-licensed; the maintainers are Rob Conery and Chase Pursley.

---

## How it works

```
db(:table)                     → %QueryCommand{table_name: "table"}     (or %DocumentCommand{})
  |> filter/sort/limit/...     → fills in the where/order/limit/params fields
  |> insert/update/delete/...  → writes cmd.sql itself and sets cmd.type
  |> MyDb.run | first | find   → (if sql is nil, select() builds the SELECT)
                               → Moebius.Database.execute → Postgrex.query(conn, sql, params)
                               → Moebius.Transformer.to_list | to_single | from_json → maps
```

- **Builders do no I/O.** Each one takes a struct and returns a new one, so you can check `cmd.sql` and `cmd.params` directly. Most tests do exactly that.
- **`use Moebius.Database`** (`database.ex`, a `__using__` macro) turns any module into a named, supervised Postgrex connection. It adds `run/1,2`, `first/1`, `find/2`, `save/2,3`, `transaction/1`, `run_batch/1`, `transact_batch/1` and `create_document_table/1,2`. `Moebius.Db` is the built-in module of this kind. Tests use `TestDb`.
- **Connection** settings come from `config :moebius, connection: [...]` (either a keyword list or `url:`) and go through `Moebius.get_connection/0`. `parse_connection/1` turns a URL into Postgrex options. The pool is `DBConnection.ConnectionPool`.
- **Transactions**: `MyDb.transaction(fn tx -> cmd |> MyDb.run(tx) end)`. When a query inside fails, `execute/2` sends its own `ROLLBACK` and then raises, and `transaction/1` catches the error and returns `{:error, msg}`.
- **Types**: `postgrex_types.ex` defines `PostgresTypes` (Jason for JSON) when the app config doesn't supply its own.
- **Mix tasks**: `moebius.create`, `moebius.drop`, `moebius.migrate` and `moebius.seed`. They shell out to `psql`, and migrate and seed only run in the test env. The aliases are `moebius.setup` and `moebius.reset`.

Navigation: `.codemap/MAP.md` lists what each directory holds, and `.codemap/recipes.md` lists which files to change for each kind of task.

---

## Current state (after phase 1, 2026-09-30)

Toolchain: Elixir 1.20.4 / OTP 29.0.5 (`.tool-versions`). Postgres 17.4 locally. `elixir: "~> 1.15"` is unchanged for library users.

| Check | Result |
|---|---|
| `mix compile` | ✅ no warnings from `lib/`. One warning remains from postgrex 0.19's generated BitString code; it goes away with the driver upgrade |
| `mix test` | ✅ **104 passed** (3 `transaction is not started` errors logged; phase 2) |
| `mix quality --strict` | ✅ format, sobelow, credo all clean |
| `mix hex.audit` | ❌ postgrex 0.19.2: CVE-2026-32687 (HIGH), CVE-2026-58225 (LOW); decimal 2.4.1: CVE-2026-32686 (MEDIUM, fix needs decimal 3.x, which postgrex 0.19 doesn't allow) |

| Dep | Locked | Latest | Note |
|---|---|---|---|
| postgrex | 0.19.2 | 0.22.4 | **held on purpose**; driver upgrade is the next step |
| decimal (transitive) | 2.4.1 | 3.1.1 | held back by postgrex |
| jason | 1.4.5 | 1.4.5 | |
| ex_doc / credo / sobelow | 0.40.4 / 1.7.19 / 0.15.0 | current | |

See `plan.md` for the phase 1 task log.

---

## Known problems in the code

**Security (SQL injection):**
- `DocumentQuery.contains/2` puts the JSON-encoded criteria straight into the SQL: `where body @> '#{encoded}'`. A value containing `'` breaks out of the string. Pass it as `$n::jsonb` instead.
- `Database.find(%QueryCommand{}, id)` builds `where id=#{id}` with no integer check, so a string id goes straight into the SQL. Use a param.
- Table and column names (`db(:x)`, `sort`, `select`, `search in:`, filter keys) are interpolated everywhere. That's acceptable only while they come from the developer. Quote identifiers, or document the limit clearly.

**Correctness and design:**
- The manual `ROLLBACK` in `Database.execute/2` works against `Postgrex.transaction/3`, and that is where the "transaction is not started" errors come from. Use `DBConnection.rollback(conn, reason)` instead.
- `transaction/1` passes the whole connection config (password included) as the options to `Postgrex.transaction`. Pass only the options the transaction needs.
- `mix.exs` has no `mod:` in `application/0`, so `Moebius.start/2` and `use Application` never run. That is dead code, or a design decision that never got finished. The README tells users to add `Moebius.Db` to their own supervision tree.
- `Moebius.BulkCommand` is never used.
- `document_query.ex` still has commented-out Poison code.
- `postgrex_types.ex` runs `Postgrex.Types.define` at compile time based on app env. That is fragile.

**CI** (`.github/workflows/elixir.yml`): it uses `actions/*@v4` and reads versions from `.tool-versions`. The warnings step fails only on `lib/` warnings until the driver upgrade.

---

## Upgrade plan

**Phase 1: get it building on current tooling (no API changes)**, ✅ done except the postgrex bump (see `plan.md`)
1. `.tool-versions` → Elixir 1.20 / OTP 29 (or the latest stable pair). Decide the minimum supported Elixir (e.g. `~> 1.17`) and set `elixir:` in `mix.exs`.
2. Deps: *(postgrex still pending: the driver upgrade)* `{:postgrex, "~> 0.22"}`, `{:jason, "~> 1.4"}`, `{:ex_doc, "~> 0.40"}`, `{:credo, "~> 1.7"}`, `{:sobelow, "~> 0.15"}`. Run `mix deps.update --all` so decimal gets its patch, then run `mix deps.get` again and confirm there are no advisories. Read the postgrex 0.20 → 0.22 changelog for breaking changes, especially around types and extensions.
3. Remove `build_embedded`. Add an empty `config/prod.exs`, or make the import conditional.
4. Fix the compiler warnings above until `mix compile --warnings-as-errors` passes.
5. CI: bump to `actions/checkout@v4` and `actions/cache@v4`, and make sure `mix quality --strict` passes.

**Phase 2: fix the known defects**
6. Parameterize `contains/2` and `find/2`. Add tests that pass a value containing `'`.
7. Replace the manual ROLLBACK with `DBConnection.rollback/2`, and pass only the needed options to `Postgrex.transaction`. Check that no "transaction is not started" errors are logged.
8. Remove the dead code: `BulkCommand`, the Poison comments, the unreachable clauses, and the unused `Moebius.start/2` (or wire it up with `mod:` on purpose).
9. Decide how to handle identifiers: quote them (`"#{String.replace(name, "\"", "\"\"")}"`) or check them against a whitelist.

**Phase 3: modernize (optional, may break the API)**
10. Consider `Postgrex.Types.define` in user code (a documented setup step) instead of the compile-time env check.
11. Add typespecs and `@doc`s to the public API so `mix docs` and dialyzer have something to work with. Also consider `Postgrex.Notifications`/LISTEN helpers, now that postgrex's notification CVEs are fixed.
12. Update the README: install version, supervision-tree setup, and the transaction example.
13. Release as 4.3.0 if nothing broke, or as 5.0.0 if phase 3 changes the API. Update `@version`, tag `v<version>` (ex_doc `source_ref` depends on it) and run `mix hex.publish`.

Verify each phase with `MIX_ENV=test mix moebius.migrate && MIX_ENV=test mix moebius.seed && mix test && mix quality`.
