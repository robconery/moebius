# Changelog

## 5.0.1

### Fixed

- Parameter validation failures now synchronize the driver before returning a connection
  to the pool, releasing the parse transaction and its table locks.
- Relational and document full-text searches preserve existing predicates, parameter
  numbering, joins where supported, explicit sorting, limits and offsets. Existing OR
  predicates are grouped before the search condition is added.
- Document writes and search-column updates are atomic. A failed search update rolls back
  the document write, including when called inside an existing transaction.
- Numeric values outside PostgreSQL's representable range are rejected before encoding,
  rather than being silently truncated by the binary codec.
- Explicit connection handles require the original process and active checkout. Expired,
  cross-process and cross-database handles are rejected for queries and document saves.
- Stream callbacks reuse their connection and transaction. A standalone stream rolls back
  callback writes on an exception or error and releases its connection on early halt.
  Suspended streams cannot be resumed after their enclosing transaction has ended.
- Unix-socket connections use transport port zero while retaining the server port in the
  socket filename.
- **A number too big for its type crashed the connection**, such as `find("99999999999")` on an `integer` key.
  That is the same kind of error now. Reading a `timestamptz` past year 9999 crashed it too;
  those are read as a `DateTime`, to the end of Postgres's range.
- **A document with an `"id"` inside its body read back under that id**, so saving it again
  overwrote a different document. The row's `id`, `created_at` and `updated_at` always win
  now, and `save/2` no longer stores them in the body under string keys either.
- **`copy/3` gave back a connection still in COPY mode when the row stream raised**, and the
  next caller got "connection lost". The connection is replaced instead. A connection that
  dies during a copy is `{:error, "connection lost: ..."}`, not an exit.

### Safety defaults and compatibility

- Requires Decimal 3.x. The package constraint no longer permits 2.x releases affected by
  [CVE-2026-32686](https://github.com/ericmj/decimal/security/advisories/GHSA-rhv4-8758-jx7v).
- Pooled connections default to `statement_timeout: "30s"`, `lock_timeout: "5s"`, and
  `idle_in_transaction_session_timeout: "30s"`. Override these for longer operations;
  `0` disables a limit. These server settings do not provide a client-side network deadline.
- **Document keys become atoms only if the atom already exists.** Every field your own code
  names does, so `doc.email` works as before. A key nobody has named stays a string. Before,
  every key of every document became a new atom, atoms are never freed, and a document store
  that holds user-shaped JSON could fill the atom table and stop the VM. Set
  `config :moebius, document_keys: :atoms` for the old behaviour, if you trust your documents.
- **`run("begin")` returns an error.** Each call may use a different connection, so the
  transaction stayed open on a pooled connection and the next caller's writes were rolled back
  with it. Use `transaction/1`.
- The transaction callback's return contract is unchanged: returning `{:error, reason}`
  commits normally. Call `rollback/1` to abort an application-level failure.
- Documented the trusted-SQL string arguments and the concurrency guarantees of
  `READ COMMITTED`, including ways to prevent lost updates.

## 5.0.0

Moebius now runs on [epgsql](https://github.com/epgsql/epgsql) 4.8 with a
[pooler](https://github.com/epgsql/pooler) 1.7 connection pool, instead of Postgrex. Both are
past 1.0 and neither has dependencies of its own. The runtime dependency tree went from
postgrex, db_connection, telemetry and decimal 2 to epgsql, pooler, jason and decimal 3.
That also closes CVE-2026-32687, CVE-2026-58225 (both in Postgrex) and CVE-2026-32686 (in
decimal 2).

The query builders and the `run`/`first`/`find`/`save`/`transaction` API are unchanged. The
breaking changes are listed below, each with its reason.

### Breaking

- **The transaction handle is a `%Moebius.Connection{}`**, not a `%DBConnection{}`. Code that
  only passes `tx` back to `run/2` and `save/3` doesn't change.
- **The `:types` config (Postgrex extensions) is gone.** Types are handled by Moebius's own
  epgsql codecs; see the README for what each Postgres type becomes.
- **Names are checked.** A table, column, function or SQL file name that isn't a plain name
  (`users`, `membership.users`, `"Order Items"`) raises `ArgumentError`. So do a sort
  direction other than `:asc`/`:desc`, an unknown join type or document operator, and a
  non-integer `limit`/`offset`. SQL fragments you write yourself are still used as written.
- **`filter(col: nil)` means `col IS NULL`** (#35). Before, it built `col = $1`, which never
  matches anything.
- **`run/1` on a statement without rows returns `{:ok, []}`**, not a bare `[]`.
- **`run_batch/1` and `transact_batch/1` return `{:ok, %Moebius.Result{}}`** per command,
  instead of Postgrex result structs.
- **An exception raised inside `transaction/1` is re-raised after the rollback.** Before,
  exceptions with a `:message` field were turned into `{:error, message}`, which hid bugs.
  Database errors, `rollback/1` and `throw({:error, reason})` still return `{:error, _}`.
- **Explicit connection options win over the parts of `:url`.** Before, `url` silently
  overrode `port:` and friends.
- **New document tables** use `id bigint generated by default as identity` and
  `updated_at timestamptz not null default now()`. Existing tables are untouched. The
  search column is built from `body ->> 'field'` (plain text, without JSON quotes).
- **Full-text search takes what people type.** `search/2` (both builders) uses
  `websearch_to_tsquery`, so `"red shoes"`, `"O'Brien"` and `"apple -pie"` work. Before,
  `to_tsquery` raised a syntax error on anything but a single word or hand-written tsquery.
- **`count/1` ignores `sort`, `limit` and `offset`.** Before, `sort |> count` built invalid
  SQL (`select count(1) ... order by`).
- **Empty builder input raises.** `insert([])`, `update([])` and `bulk_insert([])` raise
  `ArgumentError` instead of building `values($1, $0)`; `filter([])` leaves the command alone
  instead of emitting `where ;`.
- **Numeric strings longer than 34 digits are refused as parameters.** This is decimal 3's
  protection against CVE-2026-32686. Pass a `Decimal` built with `max_digits: :infinity` if
  you really mean it. Values read from the database keep full precision.
- Deprecated: Moebius.run_with_psql/2 (use `Moebius.run_script/2`, which doesn't need `psql`
  installed) and Moebius.pool_opts/0 (pool options go in the connection options).


### Fixed

- **`bulk_insert/2` read values by position.** A row whose keys were in a different order from
  the first row was inserted with its values swapped, silently. Rows are now read by key, maps
  are accepted, and a row missing a column raises.
- **A malformed uuid parameter crashed the connection process.** It is now
  `{:error, "parameter $1 must be uuid, ..."}` like every other type mismatch.
- **A password containing `:` was cut at the first colon** by `parse_connection/1`. Bad URLs
  raise `ArgumentError` (was `RuntimeError`).
- **Document field names may not contain a backslash.** With `standard_conforming_strings`
  off (a legacy server setting) a backslash could end the quoted key early.
- **`stream/2` checks `:chunk`** is a positive integer before it goes into `FETCH`.
- A pool that is busy no longer reports "isn't started"; only a missing pool process does.

### Added

- `copy/3`: bulk load any Enumerable (a lazy `Stream` included) with Postgres's binary
  `COPY` protocol. 100,000 rows load in about 130ms, 4.6x faster than 4.x's `bulk_insert` on
  the same machine. All or nothing; bad values are reported with their row and column.
- `stream/2`: read any query or document query through a server-side cursor, a chunk at a
  time. Lazy, and halting early gives the connection back.
- `explain/2`: the query plan as text. `analyze: true` runs the query inside a rolled-back
  transaction, so explaining an insert leaves nothing behind.
- Nested transactions become savepoints, so an inner one can fail on its own.
- `rollback/1` aborts the current transaction with a reason.
- Queries in the same process join an open transaction even without the `tx` argument.
- `pool_status/0`: pool size and usage.
- The pool opens all `pool_size` connections at start (as Postgrex did); set `pool_min` lower
  to let an idle pool shrink.
- Connection options: `pool_min`, `checkout_timeout`, `queue_max`, `max_lifetime`,
  `statement_timeout`, `lock_timeout`, `idle_in_transaction_session_timeout`, `settings`,
  `application_name`, `socket_dir`, `ssl`/`ssl_opts`.
- `Moebius.Error`, with the SQLSTATE code and name, detail, hint, constraint, table and column.
- Parameters are checked against the types Postgres expects before they're sent, so a wrong
  type is a clear error (`parameter $1 must be int4, got: "five"`) and never takes a
  connection down.
- `numeric` decodes to an exact `Decimal` and encodes from `Decimal`, integers, floats or
  numeric strings. Timestamps are exact to the microsecond (they're read as integers, not
  float seconds). `infinity` dates and timestamps are supported.
- `tsvector` columns come back as text instead of raising.
- `mix moebius.create/drop/migrate/seed` no longer need `psql` installed.

### Performance

Measured with the same script against 4.2 (Postgrex 0.19) on the same machine and database,
both pools holding 10 open connections:

- Single queries: median latency 5-11% lower on every operation measured (find by id 73µs
  vs 80µs), and p99 latency 10-42% lower (insert returning 118µs vs 205µs).
- 50 processes sharing the pool: about 12% slower (187ms vs 167ms for 10,000 finds). epgsql
  encodes and decodes in the connection process, where DBConnection does it in each caller.
- `bulk_insert` + `transact_batch` of 100k rows: about 24% slower (739ms vs 595ms). Use
  `copy/3` instead, at 130ms.

### Fixed

- `find/2` put the id into the SQL (`find("1 or 1=1")` returned a row). It's a parameter now.
- `DocumentQuery.contains/2` put the JSON into the SQL as a literal, so a `'` in a value broke
  the query and could be used for injection. It's a parameter now.
- `DocumentQuery` field names in `filter/4`, `exists/3`, `sort/3` and `search/2` are quoted,
  so any key is safe.
- `db(:docs) |> delete(id) |> first()` ran a select and deleted nothing.
- Saving to a new document table from several processes at once lost writes to a race in
  `create table if not exists`. Creation now takes an advisory lock.
- Document tables with a schema (`public.docs`) got invalid index names.
- A document query that failed for any reason other than a missing table retried forever.
- `filter(:col, in: [])` built `IN()`, a syntax error. It now matches nothing (and
  `not_in: []` matches everything).
- The `DBConnection.TransactionError` log noise after a failed transaction is gone.
- The `Moebius.QueryFilter` doctests were wrong and weren't run. They run now.
