# Glossary — codenames & domain terms

> Mismatched vocabulary = wasted searches. Map jargon → meaning here.

- **QueryCommand** — struct piped through relational builders; holds `sql`, `params`, `where`, `type` (:select/:insert/:update/:delete/:count), `conn` (the database module that runs it). `lib/moebius/query_command.ex`
- **DocumentCommand** — same idea for JSONB document tables (`id`, `body jsonb`, `search tsvector`). `lib/moebius/document_command.ex`
- **`use Moebius.Database`** — macro that turns a user module (e.g. `TestDb`) into a database with its own pooler pool: `run/first/find/save/transaction/rollback/stream/explain/run_batch/pool_status`. `lib/moebius/database.ex`
- **pool / member** — pooler terms. One pool per database module, named after it; a member is one epgsql connection process. `lib/moebius/pool.ex`
- **held connection** — a connection pinned to the calling process (process dict key `{Moebius.Pool, :held, pool}`) while a transaction or stream is open; every query in that process on that pool reuses it
- **broken connection** — one whose protocol state is unknown (it died, or a rollback failed). Flagged in the process dict by `Moebius.Connection`; the pool returns it as `:fail` and pooler replaces it
- **Moebius.Connection** — the `tx` handle passed to transaction callbacks (`%Moebius.Connection{pool, pid}`); also the module that calls epgsql
- **Moebius.Result** — raw result of one statement (`command`, `columns`, `rows`, `num_rows`) before the Transformer turns it into maps
- **Moebius.Error** — exception with SQLSTATE `code`/`name`, `message`, `detail`, ...; the public API returns only its message as `{:error, message}`
- **codec** — an `:epgsql_codec` module that encodes/decodes one set of Postgres types. `lib/moebius/codec/`
- **Params.check** — checks each parameter against the type Postgres parsed, before epgsql encodes it (a wrong type would crash the connection process). `lib/moebius/params.ex`
- **Identifier** — the name checks for everything interpolated into SQL (`name!/1`, `json_key/1`, `direction!/1`, `script!/1`). `lib/moebius/identifier.ex`
- **TestDb** — the test suite's DB module, `test/support/test_db.ex`; **Moebius.TestData** — shared test setup, `test/support/test_data.ex`
- **CommandBatch / transact_batch** — list of commands run together, optionally in one transaction. `database.ex`
- **bulk_insert** — multi-row insert chunked at 20,000 params per command. `query.ex` `bulk_insert/2`
- **sql_file** — run a `.sql` file from the `:scripts` config dir by name. `query.ex`
- **run_script** — run a multi-statement SQL string on its own connection (mix tasks). `lib/moebius.ex`
- **function / function_command** — call a Postgres stored function. `query.ex`
- **searchable / search** — Postgres full-text search (tsvector); documents keep a `search` column updated on save
- **Moebius.Db** — the ready-made database module in `lib/moebius.ex`, configured by `config :moebius, connection:`
