# epgsql, as Moebius uses it

epgsql 4.x (BSD-3). Zero dependencies. Source: https://github.com/epgsql/epgsql

## Connecting

```elixir
{:ok, conn} =
  :epgsql.connect(%{
    host: ~c"localhost",          # charlist or binary both fine
    port: 5432,
    username: "postgres",
    password: "postgres",         # or a 0-arity fun, which keeps it out of crash logs
    database: "moebius_test",
    timeout: 5_000,               # socket connect timeout only
    nulls: [nil, :null],          # first element is what NULL decodes to
    codecs: [{:epgsql_codec_json, Jason}],
    application_name: "moebius"
  })
```

- `connect/1` spawns the connection process **linked to the caller**. Under pooler the caller is a supervised starter, so it ends up correctly owned.
- `password` as a fun keeps plaintext out of crash reports. Do that.
- `ssl: true | :required`, `ssl_opts: [...]` pass through to `:ssl`.
- Unix sockets: `host: {:local, "/tmp/.s.PGSQL.5432"}`.

## Queries

| Call | Protocol | Params | Types back | Multiple statements |
|---|---|---|---|---|
| `:epgsql.squery(c, sql)` | simple | no | **all text binaries** | yes, returns a list of results |
| `:epgsql.equery(c, sql, params)` | extended (parse+bind+execute, unnamed stmt) | `$1..$n` | decoded Erlang terms | no |
| `:epgsql.prepared_query(c, stmt, params)` | extended, named stmt | yes | decoded | no |
| `:epgsql.execute_batch(c, sql, [params, ...])` | extended, pipelined | yes | decoded | the same statement N times, one round-trip |

`equery` does a parse and describe round-trip first so it knows parameter types. You don't pass types.

Result shapes:

```elixir
{:ok, columns, rows}          # select
{:ok, count}                  # insert/update/delete without returning
{:ok, count, columns, rows}   # ... with returning
{:error, error_record}        # server error
```

- `rows` is a list of **tuples**, in column order.
- `columns` is a list of `#column{name, type, oid, size, modifier, format, table_oid, table_attr_number}` records.
- `squery` on a multi-statement string returns a **list** of the shapes above, one per statement. If one fails, the list ends with `{:error, _}`.

## The command tag

`:epgsql.get_cmd_status(c)` returns the last command's tag: `{:insert, n}`, `{:update, n}`, `{:delete, n}`, `:select`, `:commit`, `:rollback` and so on. Use it to tell a delete from an update when both came back as `{:ok, count}`. After `COMMIT` on a failed transaction the status is `:rollback`. That is how you detect it.

## Errors

```elixir
{:error, {:error, severity, code, codename, message, extra}}
#            ^ the record tag is :error, so the tuple starts with :error twice
```

- `code` is the SQLSTATE binary, e.g. `"42P01"` (undefined_table), `"23505"` (unique_violation), `"23503"` (foreign_key_violation), `"57014"` (query_canceled, which statement_timeout triggers).
- `codename` is the atom version: `:undefined_table`, `:unique_violation`.
- **Match on `codename`/`code`, never on message text.** Messages are translated when the server's `lc_messages` is not English.
- `extra` is a keyword list: `detail`, `hint`, `constraint_name`, `table_name`, `column_name`, `position`.
- Non-server errors are plain atoms or tuples: `:closed`, `:timeout`, `:sync_required`, `{:unsupported_auth_method, m}`.
- After an error on the extended protocol epgsql resyncs itself for `equery`. For low-level parse/bind/execute you call `:epgsql.sync/1`.

## Default type mapping (and what Moebius does about it)

| Postgres | epgsql returns | Moebius converts to |
|---|---|---|
| NULL | first entry of `nulls` | `nil` (set `nulls: [nil, :null]`) |
| int2/4/8 | integer | same |
| float4/8 | float, or `:nan`, `:plus_infinity`, `:minus_infinity` | same |
| **numeric** | **text binary**, e.g. `"12.50"` (no binary codec) | `Decimal` if available, else the binary |
| bool | `true` / `false` | same |
| text, varchar, char | binary | same |
| uuid | binary string `"a0ee..."` | same |
| json / jsonb | binary, or decoded with the configured codec | map with string keys (Jason codec) |
| date | `{y, m, d}` | `Date` |
| time | `{h, m, s_float}` | `Time` |
| timestamp | `{{y,m,d},{h,m,s_float}}` | `NaiveDateTime` |
| timestamptz | same tuple, in UTC | `DateTime` in `Etc/UTC` |
| interval | `{{h,m,s}, days, months}` | left as is |
| arrays | lists (nested for multidim) | elements converted as above |
| tsvector, unknown types | text binary | same |

Parameters going in: `Date`, `Time`, `NaiveDateTime` and `DateTime` must be turned into the tuple forms above. `nil` works directly once `nulls` includes it. Integers, floats, binaries, booleans, lists and maps (for json/jsonb with the codec) go straight through. A `Decimal` must be sent as its string form (`Decimal.to_string/2`), because epgsql encodes numeric parameters as text.

Seconds come back as a **float** when there's a fractional part (`12.5`) and an integer otherwise. Handle both.

## Transactions

```elixir
:epgsql.with_transaction(conn, fn c -> ... end, reraise: true, ensure_committed: true)
```

- Sends `BEGIN`, then `COMMIT` on normal return, and `ROLLBACK` if the fun raises.
- With `reraise: false` (the `with_transaction/2` default) it returns `{:rollback, reason}` instead of raising.
- `ensure_committed: true` checks the command status after COMMIT and raises `ensure_committed_failed` when Postgres actually rolled back (which happens when a statement inside failed and the caller carried on).
- **A failed statement poisons the transaction.** Every later statement errors with `25P02` (in_failed_sql_transaction) until ROLLBACK. Moebius stops at the first error and rolls back.
- Build Moebius's own transaction on `BEGIN`/`COMMIT`/`ROLLBACK` via `squery` if we need more control than `with_transaction` gives (it's three lines).

## Timeouts

- **All synchronous calls are `gen_server:call(..., :infinity)`.** A slow query blocks the caller forever from the client's point of view.
- So bound queries on the server: `SET statement_timeout = '30s'` per session (run it right after connect), or per transaction with `SET LOCAL`.
- `:epgsql.cancel(conn)` sends a cancel request on a side connection. The query then returns `{:error, #error{codename: :query_canceled}}`.

## Gotchas

- One process at a time per connection (the unnamed statement is shared).
- `squery` returns everything as text. Don't use it for user-facing queries; use it for DDL, multi-statement scripts and `BEGIN`/`COMMIT`.
- `execute_batch/3` stops at the first error; the result list is shorter than the batch and ends with `{:error, _}`.
- Max 65,535 bind parameters per statement (protocol limit, Int16 count).
- The connection process decodes rows, then copies them to the caller. Huge result sets cost memory twice. Use a cursor (`DECLARE ... CURSOR` + `FETCH`) or `epgsqli` for exports.
