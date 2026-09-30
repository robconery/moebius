# Glossary — codenames & domain terms

> Mismatched vocabulary = wasted searches. Map jargon → meaning here.

- **QueryCommand** — struct piped through relational builders; holds `sql`, `params`, `where`, `type` (:select/:insert/:update/:delete/:count). `lib/moebius/query_command.ex`
- **DocumentCommand** — same idea for JSONB document tables (`id`, `body jsonb`, `search tsvector`). `lib/moebius/document_command.ex`
- **`use Moebius.Database`** — macro that turns a user module (e.g. `TestDb`) into a supervised Postgrex connection with `run/first/find/save/transaction/run_batch`. `lib/moebius/database.ex`
- **TestDb** — the test suite's DB module, defined in `test/test_helper.exs`
- **CommandBatch / transact_batch** — list of commands run together, optionally in one transaction. `database.ex`
- **BulkCommand / bulk_insert** — multi-row insert chunked by params. `query.ex` `bulk_insert/2`
- **sql_file** — run a `.sql` file from the `:scripts` config dir by atom name. `query.ex`
- **function / function_command** — call a Postgres stored function. `query.ex`
- **searchable / search** — Postgres full-text search (tsvector); documents keep a `search` column updated on save
- **Moebius.Db** — tiny module at top of `lib/moebius.ex` (legacy default DB module)
- **PostgresTypes** — Postgrex type module with Jason JSON; override via `:moebius, types:`. `postgrex_types.ex`
