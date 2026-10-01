# Moebius

[![Hex.pm](https://img.shields.io/hexpm/v/moebius.svg)](https://hex.pm/packages/moebius)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/moebius)
[![CI](https://github.com/robconery/moebius/actions/workflows/elixir.yml/badge.svg)](https://github.com/robconery/moebius/actions/workflows/elixir.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**A functional query library for Elixir and PostgreSQL.** You pipe small functions together to build a query, then hand it to a database to run. You get plain maps back.

```elixir
import Moebius.Query

{:ok, users} =
  db(:users)
  |> filter(:order_count, gt: 5)
  |> sort(:last, :asc)
  |> limit(20)
  |> Moebius.Db.run()
```

Moebius is *not* an ORM. There are no schemas, no mappings and no migrations; only queries and data. It leans on PostgreSQL as hard as it can: JSONB documents, full-text search, `COPY`, cursors, savepoints and `EXPLAIN` are all a function call away.

- [Why Moebius exists](#why-moebius-exists)
- [What's new in 5.0](#whats-new-in-50)
- [Installation](#installation) and [configuration](#configuration)
- [Querying](#querying), [writing](#inserting-updating-and-deleting), [joins](#joins), [aggregates](#aggregates), [full-text search](#full-text-search)
- [Documents (JSONB)](#documents-jsonb)
- [SQL files and functions](#sql-files-and-functions)
- [Bulk loading](#bulk-loading), [streaming](#streaming-large-results), [transactions](#transactions), [EXPLAIN](#asking-postgres-how-it-will-run-a-query)
- [Types](#types), [errors](#errors) and [safety](#safety)
- [Contributing](#contributing)

## Why Moebius exists

Elixir is lucky. The people who build the language also built Ecto and Postgrex, and both are excellent. Most languages don't get that. If Ecto fits the way you think, use it; it's a great piece of work and it isn't going anywhere.

But the folks who make a language shouldn't have to make *every* tool for it too. That's a lot to carry, and one of the nice things about open source is that the rest of us can pitch in with a different take. Moebius is one of those takes.

It started in 2015 as a port of the ideas in [MassiveJS](https://github.com/robconery/massive-js): talk to Postgres directly, treat SQL as a friend rather than something to hide, and keep the API small enough to hold in your head. Queries are data. Functions transform them. The database runs them. That's the whole idea, and it happens to fit Elixir very well.

So Moebius is for you if:

- You like SQL and want to write it (or something close to it) instead of mapping it.
- You want to store documents in Postgres and query them without setting up a separate database.
- You'd rather have maps than structs, and a pipe than a schema.

## What's new in 5.0

**5.0.1 fixes transaction cleanup, scoped searches, atomic document saves, numeric bounds,
connection ownership, streaming, and Unix sockets.** It also enables configurable server
timeouts by default. See [CHANGELOG.md](CHANGELOG.md) for the release details.

5.0 swaps the driver. Moebius used to run on Postgrex; it now runs on [epgsql](https://github.com/epgsql/epgsql), the Erlang PostgreSQL driver, with a [pooler](https://github.com/epgsql/pooler) connection pool. The query builders and the `run`/`first`/`find`/`save`/`transaction` API didn't change.

### Why change the driver?

Postgrex is a good driver and this isn't a knock on it. There were two practical reasons.

**Stability.** Postgrex has been a 0.x library for its whole life, which means any minor release is allowed to break things. A library that depends on it has to pin `~> 0.19` and ask its users to live with that pin. epgsql has been past 1.0 since 2015 and on 4.x since 2018. pooler, from the same group, is at 1.7. Neither pulls in anything else.

**Security.** Postgrex held `decimal` at 2.x, which kept a known vulnerability in every app that installed Moebius. With 5.0, `mix hex.audit` is clean.

| | 4.2 (Postgrex) | 5.0 (epgsql) |
|---|---|---|
| Driver | postgrex 0.19.2 | epgsql 4.8.0 (no deps) |
| Pool | db_connection 2.7.0 + telemetry | pooler 1.7.0 (no deps) |
| Decimal | 2.4.1 | 3.1.1 |
| Open CVEs | 3 (CVE-2026-32687, CVE-2026-58225, CVE-2026-32686) | 0 |
| Needs `psql` installed for mix tasks | yes | no |
| Tests | 104 | 209 |

Since a major version was happening anyway, 5.0 also fixes some old behavior that couldn't be fixed without breaking something. The full list, with the reason for each, is in [CHANGELOG.md](CHANGELOG.md). The ones you're most likely to hit:

- The transaction handle is a `%Moebius.Connection{}`. If you only pass `tx` back to `run/2` and `save/3`, nothing changes.
- Table, column and function names are checked, and a bad one raises `ArgumentError`.
- `filter(col: nil)` means `col IS NULL` (it used to build `col = $1`, which never matched).
- `run/1` on a statement with no rows returns `{:ok, []}`, not a bare `[]`.
- An exception raised inside `transaction/1` is re-raised after the rollback instead of being turned into `{:error, message}`.
- The `:types` config (Postgrex extensions) is gone. Types are handled by Moebius's own codecs.

### New in 5.0

- [`copy/3`](#bulk-loading): bulk load any Enumerable with Postgres's binary `COPY` protocol.
- [`stream/2`](#streaming-large-results): read a query through a server-side cursor, a chunk at a time.
- [`explain/2`](#asking-postgres-how-it-will-run-a-query): the query plan as text, with an `analyze` that leaves nothing behind.
- [Nested transactions](#transactions) become savepoints, and `rollback/1` aborts with a reason.
- [Exact types](#types): `numeric` is a `Decimal` both ways, timestamps are exact to the microsecond, `infinity` works.
- [`Moebius.Error`](#errors), with the SQLSTATE code, detail, hint, constraint, table and column.
- Parameters are [checked before they're sent](#safety), so a wrong type is a clear error and never takes a connection down.
- A pool that survives an outage: if Postgres goes away, calls return `{:error, message}` until it's back, and nothing else in your supervision tree restarts.

### Bugs the new tests found

The test suite was rewritten before any driver code changed, so that every test creates the rows it checks and asserts an exact value. Then the driver swap added tests for every type, failure and race. They turned up eleven bugs, all fixed in 5.0. Two of them were SQL injection:

- `find("1 or 1=1")` returned a row, because the id was pasted into the SQL.
- A `'` in a `DocumentQuery.contains/2` value broke out of the SQL string.

The others: concurrent saves to a new document table could lose writes, `delete(id) |> first()` deleted nothing, `filter(col: nil)` never matched, a `url` silently overrode an explicit `port:`, `in: []` built invalid SQL, document tables in a schema got bad index names, a failed document query could retry forever, and two doctests were wrong and never ran. The details are in the [changelog](CHANGELOG.md#fixed).

### Benchmarks

Same script, same laptop, same Postgres 17 database, run against 4.2 and 5.0 with both pools holding ten open connections. Medians over three alternating runs.

| Operation | 4.2 median | 5.0 median | 4.2 p99 | 5.0 p99 |
|---|---:|---:|---:|---:|
| find by id | 80 µs | 73 µs | 313 µs | 236 µs |
| filter, 100 rows | 215 µs | 191 µs | 332 µs | 228 µs |
| insert returning | 84 µs | 79 µs | 205 µs | 118 µs |
| count | 184 µs | 167 µs | 314 µs | 199 µs |
| document save | 87 µs | 83 µs | 181 µs | 121 µs |
| document contains | 97 µs | 92 µs | 136 µs | 122 µs |

| Workload | 4.2 | 5.0 |
|---|---:|---:|
| Load 100,000 rows with `bulk_insert` + `transact_batch` | 595 ms | 739 ms |
| Load 100,000 rows with `copy/3` | n/a | **130 ms** |
| 50 processes × 200 finds on a 10-connection pool | 167 ms | 187 ms |

Single queries are 5 to 11% faster at the median and 10 to 42% faster at p99. Under heavy concurrency 5.0 is about 12% slower, because epgsql encodes and decodes inside its connection processes while DBConnection lends the socket to each caller. `bulk_insert` is slower for the same reason; use `copy/3`, which is 4.6 times faster than 4.2's `bulk_insert`.

## Installation

Add Moebius to your dependencies in `mix.exs`:

```elixir
def deps do
  [{:moebius, "~> 5.0"}]
end
```

Then add the default database to your application's supervision tree:

```elixir
children = [
  Moebius.Db
]
```

Run `mix deps.get` and you're good to go. Moebius needs Elixir 1.15 or later.

## Configuration

Put your connection details in `config/config.exs` (or `runtime.exs`):

```elixir
config :moebius,
  connection: [
    hostname: "localhost",
    username: "postgres",
    password: "postgres",
    database: "my_app"
  ],
  scripts: "priv/sql"
```

A URL works too:

```elixir
config :moebius, connection: [url: "postgresql://user:password@host/database"]
```

A missing username or password falls back to `PGUSER` and `PGPASSWORD`. If you pass both a `url` and explicit options, the explicit options win. `scripts` is the directory for [SQL files](#sql-files-and-functions).

These options are worth knowing:

```elixir
config :moebius, connection: [
  url: "postgresql://user:password@host/database",
  pool_size: 10,                # the most connections to open (default 10)
  pool_min: 10,                 # opened at start and kept when idle (default: pool_size)
  checkout_timeout: 5_000,      # how long a call waits for a free connection, in ms
  statement_timeout: "30s",     # maximum time for a statement (default 30s)
  lock_timeout: "5s",           # maximum wait for each lock (default 5s)
  idle_in_transaction_session_timeout: "30s", # idle transaction limit (default 30s)
  application_name: "my_app",   # shows up in pg_stat_activity
  ssl: true                     # or :required, with ssl_opts: [...]
]
```

Also supported: `queue_max`, `max_lifetime`, `lock_timeout`, `idle_in_transaction_session_timeout`, `settings` (any other session settings) and `socket_dir`.

These timeout defaults apply to pooled connections. Override them for long-running queries
or COPY imports; `0` disables a limit. They bound work on the server, but do not impose a
client deadline when the network stops responding. `run_script/2` opens a separate connection
and does not apply the pool's timeout defaults.

### Your own database modules

`Moebius.Db` is a ready-made database. You can make your own, each with its own pool:

```elixir
defmodule MyApp.Db do
  use Moebius.Database
end
```

Each database module is one child in your supervision tree. With no arguments it reads the `:connection` config; pass options to point it somewhere else:

```elixir
config :moebius,
  connection: [url: "postgresql://localhost/my_app"],
  reporting: [url: "postgresql://replica/my_app", pool_size: 4]
```

```elixir
defmodule MyApp.ReportingDb do
  use Moebius.Database
end

children = [
  MyApp.Db,
  {MyApp.ReportingDb, Moebius.get_connection(:reporting)}
]
```

That's handy for a read replica, a second database, or just keeping a slow reporting workload away from your web requests. (Many thanks to [Peter Hamilton](https://github.com/hamiltop) for the original idea.)

The rest of this README uses `Moebius.Db`, but every function works the same on your own modules. `pool_status/0` tells you how busy a pool is:

```elixir
Moebius.Db.pool_status()
#=> %{max_count: 10, in_use_count: 1, free_count: 9, ...}
```

## Querying

Every query follows the same flow: build a command with the builder functions, then pass it to a database. Builders never touch the database, so you can inspect `cmd.sql` and `cmd.params` any time.

```elixir
import Moebius.Query

cmd = db(:users) |> filter(email: "rob@example.com")
cmd.params  #=> ["rob@example.com"]

{:ok, user} = cmd |> Moebius.Db.first()
```

You run a command with one of these:

| Function | Returns |
|---|---|
| `run/1` | `{:ok, [map]}` for a select, `{:ok, map}` for insert/update, `{:ok, %{deleted: n}}` for delete |
| `first/1` | `{:ok, map}` or `{:ok, nil}` |
| `find/2` | `{:ok, map}` or `{:ok, nil}`, by primary key |

```elixir
{:ok, user}  = db(:users) |> Moebius.Db.find(42)
{:ok, users} = db(:users) |> Moebius.Db.run()
{:ok, %{count: 1024}} = db(:users) |> count() |> Moebius.Db.first()
```

### Filtering

Pass a keyword list for equality:

```elixir
db(:users) |> filter(first: "Rob", last: "Conery")
# where first = $1 and last = $2
```

Or a column and an operator:

```elixir
db(:users) |> filter(:name, eq: "mark")          # =
db(:users) |> filter(:name, neq: "mark")         # !=
db(:users) |> filter(:order_count, gt: 5)        # >
db(:users) |> filter(:order_count, gte: 5)       # >=
db(:users) |> filter(:order_count, lt: 5)        # <
db(:users) |> filter(:order_count, lte: 5)       # <=
db(:users) |> filter(:name, in: ["mark", "biff", "skip"])
db(:users) |> filter(:name, ["mark", "biff", "skip"])       # same as in:
db(:users) |> filter(:name, not_in: ["mark", "biff"])       # or nin:
```

`nil` means `IS NULL`, and `neq: nil` means `IS NOT NULL`:

```elixir
db(:users) |> filter(deleted_at: nil)
db(:users) |> filter(:deleted_at, neq: nil)
```

An empty `in: []` matches nothing, and an empty `not_in: []` matches everything.

When you need something the helpers don't cover, write the condition yourself. Values still go in as parameters:

```elixir
db(:users) |> filter("created_at > now() - interval '7 days'")
db(:users) |> filter("email ilike $1", "%@example.com")
```

Filters stack, so you can pipe as many as you like.

### Sorting, paging and picking columns

```elixir
{:ok, page} =
  db(:users)
  |> filter(:order_count, gt: 0)
  |> sort(:order_count, :desc)
  |> limit(25)
  |> offset(50)
  |> select([:id, :email, :order_count])
  |> Moebius.Db.run()
```

`select/2` writes the SQL from everything piped in before it, so it goes last. You only need it to pick columns; without it you get `*`.

`sort/2` takes a list for more than one column: `sort(id: :asc, name: :desc)`. `skip/2` is an alias for `offset/2`. `db(:users) |> last(:id) |> Moebius.Db.first()` gets the newest row.

If you'd rather read something closer to SQL, there are aliases: `from` for `db`, `where` for `filter`, and `order_by` for `sort`.

```elixir
from(:users)
|> where(:order_count, gt: 5)
|> order_by(:email)
|> Moebius.Db.run()
```

### Just SQL

If an abstraction is in your way, skip it:

```elixir
{:ok, rows} = Moebius.Db.run("select id, email from users where id = $1", [1])
```

## Inserting, updating and deleting

`insert` returns the new row:

```elixir
{:ok, user} =
  db(:users)
  |> insert(email: "frodo@shire.me", first: "Frodo", last: "Baggins")
  |> Moebius.Db.run()

user.id #=> 1
```

`update` changes whatever the filter matches, and returns the updated row:

```elixir
{:ok, user} =
  db(:users)
  |> filter(id: 1)
  |> update(email: "frodo@rivendell.me")
  |> Moebius.Db.run()
```

`delete` works the same way and returns a count:

```elixir
{:ok, %{deleted: 3}} =
  db(:sessions)
  |> filter("expires_at < now()")
  |> delete()
  |> Moebius.Db.run()
```

## Joins

Tables can be atoms or strings. The defaults follow the usual naming convention (`customer.id` = `order.customer_id`), and you can override any of it:

```elixir
db(:customer)
|> join(:order)
|> select()
|> Moebius.Db.run()

db(:customer)
|> join(:order, on: :customer)
|> join(:item, on: :order)
|> select()
|> Moebius.Db.run()

db(:customer)
|> join(:order, join: :left, foreign_key: :cust_id, primary_key: :id)
|> select()
|> Moebius.Db.run()
```

The options are `:join` (`:inner` by default, or `:left`, `:right`, `:full`, `:cross`), `:on`, `:foreign_key`, `:primary_key` and `:using`.

## Aggregates

Aggregates are built the way you'd think about them: gather the rows (`map`), group them (`group`) and reduce them (`reduce`):

```elixir
{:ok, %{sum: 5}} =
  db(:users)
  |> map("order_count > 1")
  |> reduce(:sum, :order_count)
  |> Moebius.Db.first()

{:ok, rows} =
  db(:users)
  |> map("order_count > 1")
  |> group(:email)
  |> reduce(:sum, :order_count)
  |> Moebius.Db.run()
#=> [%{email: "b@test.com", sum: 2}, %{email: "c@test.com", sum: 3}]
```

Any Postgres aggregate works: `:avg`, `:min`, `:max`, `:count` and so on. For anything fancier (window functions, CTEs), a [SQL file](#sql-files-and-functions) is the better tool.

## Full-text search

Postgres has very good full-text search built in, and Moebius will build the `tsvector` query for you, ranked with `ts_rank`:

```elixir
{:ok, results} =
  db(:users)
  |> search(for: "mike", in: [:first, :last, :email])
  |> Moebius.Db.run()
```

## Documents (JSONB)

Moebius can use Postgres as a document store. You don't create tables or write migrations; you save a map and Moebius takes care of the rest.

```elixir
import Moebius.DocumentQuery

{:ok, friend} =
  db(:friends)
  |> Moebius.Db.save(%{email: "moe@test.com", name: "Moe Test", tags: ["best"], spent: 250})

friend.id #=> 1
```

If `friends` didn't exist, `save/2` just created it:

```sql
create table friends(
  id bigint generated by default as identity primary key,
  body jsonb not null,
  search tsvector,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_friends_search on friends using GIN(search);
create index idx_friends on friends using GIN(body jsonb_path_ops);
```

Saving a document that has an `id` updates it:

```elixir
{:ok, friend} = db(:friends) |> Moebius.Db.save(%{friend | name: "Moe Howard"})
```

The `id`, `created_at` and `updated_at` you get back are the row's own. They are never stored inside the document.

Keys come back as atoms when the atom already exists, which covers every field your code mentions (`friend.email`). A key nobody has named stays a string. Atoms are never freed, so this keeps documents with keys chosen by users, like a webhook payload, from filling the atom table. If you trust your documents and want every key as an atom, set `config :moebius, document_keys: :atoms`.

### Querying documents

`contains/2` uses the `@>` operator and the GIN index, so it's fast. Use it whenever you can:

```elixir
{:ok, friends} = db(:friends) |> contains(email: "moe@test.com") |> Moebius.Db.run()
{:ok, friend}  = db(:friends) |> Moebius.Db.find(1)
```

For comparisons, `filter/4` works on any key. It can't use the GIN index, so it scans the table:

```elixir
{:ok, big_spenders} =
  db(:friends)
  |> filter(:spent, ">", 100)
  |> sort(:name)
  |> limit(10)
  |> Moebius.Db.run()
```

`exists/3` uses the `?` operator, which is handy for arrays:

```elixir
{:ok, besties} = db(:friends) |> exists(:tags, "best") |> Moebius.Db.run()
```

### Searching documents

Tell Moebius which keys to index when you save, and it keeps the `search` column up to date:

```elixir
db(:products)
|> searchable([:name, :description])
|> Moebius.Db.save(%{name: "Buffalo Wings", description: "Spicy chicken wings"})

{:ok, results} = db(:products) |> search("spicy") |> Moebius.Db.run()
```

You can also search keys on the fly, without the index: `search(for: "spicy", in: [:name, :description])`.

A document save and its search-column update run in one transaction. If either fails,
neither write is committed. Both relational and document searches preserve preceding
filters, parameters, sorting, limits and offsets. Put `search/2` last in the builder pipeline,
before calling `run/1`, `first/1` or `stream/2`.

### Structs

Save a struct and you get the same struct back, with its `id`:

```elixir
defmodule Candy do
  defstruct id: nil, sticky: true, chocolate: "gooey"
end

{:ok, %Candy{id: 1, sticky: true}} = db(:candies) |> Moebius.Db.save(%Candy{})
```

## SQL files and functions

Some people love SQL. I'm one of them. When a query gets hard (a window function, a CTE, a report), put it in a `.sql` file in your `scripts` directory and run it by name:

```sql
-- priv/sql/top_customers.sql
select c.id, c.email, sum(o.total) as spent
from customers c
join orders o on o.customer_id = c.id
where o.created_at > $1
group by c.id
order by spent desc
limit 10;
```

```elixir
{:ok, top} = sql_file(:top_customers, [~D[2026-01-01]]) |> Moebius.Db.run()
```

Postgres functions work the same way:

```elixir
{:ok, [%{upper: "MOEBIUS"}]} = function(:upper, "moebius") |> Moebius.Db.run()
```

## Bulk loading

For lots of rows, use `copy/3`. It speaks Postgres's binary `COPY` protocol, the same one `pg_dump` and `pg_restore` use: rows stream to the server in one command, with no SQL to parse and no parameter limit. 100,000 rows load in about 130 ms on a laptop.

```elixir
rows = [
  %{first_name: "John", last_name: "Lennon", city: "Liverpool"},
  %{first_name: "Paul", last_name: "McCartney", city: "Liverpool"}
]

{:ok, 2} = Moebius.Db.copy(:people, rows)
```

`rows` can be any Enumerable, including a lazy `Stream`, and it's sent in chunks, so memory stays flat even for a file much bigger than RAM:

```elixir
File.stream!("people.csv")
|> CSV.decode!(headers: true)
|> Stream.map(&%{first_name: &1["first"], last_name: &1["last"]})
|> Moebius.Db.copy(:people)
```

It's all or nothing. If any row fails (a constraint, or a value of the wrong type, which is reported with its row and column), nothing is written. Inside a transaction it joins the transaction.

`bulk_insert` still works too. It builds multi-row `INSERT` commands split to stay under Postgres's parameter limit, which you run with `run_batch/1` or, all or nothing, `transact_batch/1`:

```elixir
db(:people)
|> bulk_insert(rows)
|> Moebius.Db.transact_batch()
```

## Streaming large results

`stream/2` reads a query through a server-side cursor, a chunk at a time, so a million rows never sit in memory at once. It's an Elixir `Stream`, so nothing runs until you read it, and stopping early gives the connection back:

```elixir
db(:events)
|> filter(:kind, eq: "signup")
|> sort(:id)
|> Moebius.Db.stream(chunk: 1_000)
|> Stream.each(&send_welcome_email/1)
|> Stream.run()
```

It works with document queries too. Enumerate and resume the stream in the same process.
That process holds the connection until the stream ends. Database calls in stream callbacks
reuse that connection and transaction. A standalone stream commits its callback writes on
completion or early halt, and rolls them back if fetching or consuming rows raises or throws.
When enumerated inside `transaction/1`, the enclosing transaction controls the outcome.

## Transactions

Pass a function to `transaction/1`. It gets a connection handle, which you pass to each query. Whatever the function returns, `transaction/1` returns. If a statement fails, everything rolls back and you get `{:error, message}`:

```elixir
Moebius.Db.transaction(fn tx ->
  {:ok, user} =
    db(:users)
    |> insert(email: "frodo@shire.me")
    |> Moebius.Db.run(tx)

  {:ok, _log} =
    db(:logs)
    |> insert(user_id: user.id, log: "Hi Frodo")
    |> Moebius.Db.run(tx)

  user
end)
#=> %{id: 1, email: "frodo@shire.me", ...}
```

A few more things:

- Queries in the same process join the open transaction even if you forget to pass `tx`.
- `Moebius.Db.rollback(reason)` aborts the transaction, which then returns `{:error, reason}`.
- Returning `{:error, reason}` from the callback does **not** abort it; that is a normal
  return and commits. Use `rollback/1` for application-level failures.
- A connection handle may only be used by its owning process during its active checkout.
  Do not retain it after the callback returns or pass it to a Task or another database.
- If your function raises, the transaction rolls back and the exception is re-raised.
- A transaction inside a transaction becomes a savepoint, so the inner one can fail without taking the outer one down:

```elixir
Moebius.Db.transaction(fn tx ->
  {:ok, order} = db(:orders) |> insert(total: 100) |> Moebius.Db.run(tx)

  # if this fails, only the payment is rolled back; the order stays
  Moebius.Db.transaction(fn tx ->
    {:ok, _} = db(:payments) |> insert(order_id: order.id) |> Moebius.Db.run(tx)
    unless card_ok?(order), do: Moebius.Db.rollback(:declined)
  end)

  order
end)
```

PostgreSQL's default isolation level is `READ COMMITTED`. It prevents dirty reads, but a
transaction alone does not prevent lost updates in a read-modify-write operation. Use an
atomic update such as `SET balance = balance + $1`, lock the row with `SELECT ... FOR UPDATE`,
or use optimistic version checks. For stronger isolation, issue `SET TRANSACTION ISOLATION
LEVEL SERIALIZABLE` before the transaction's first data query and retry the whole transaction
on serialization failure. Acquire multiple row locks in a consistent order to reduce deadlocks.

## Asking Postgres how it will run a query

`explain/2` returns the plan as text. It's the fastest way to find out whether a query uses your indexes:

```elixir
{:ok, plan} = db(:users) |> filter(email: "a@b.com") |> Moebius.Db.explain()
# Index Scan using users_email_key on users  (cost=0.15..8.17 rows=1 width=...)

{:ok, plan} = db(:users) |> filter(first: "Rob") |> Moebius.Db.explain(analyze: true)
# Seq Scan on users ... (actual time=0.010..0.011 rows=1 loops=1)
```

With `analyze: true` the query really runs, inside a transaction that's rolled back, so explaining an insert leaves nothing behind.

## Types

Values come back as you'd expect, and the same types work as parameters:

| Postgres | Elixir |
|---|---|
| `integer`, `bigint`, `smallint` | integer |
| `real`, `double precision` | float |
| `numeric` | `Decimal`, exact (encodes from `Decimal`, integers, floats or numeric strings) |
| `text`, `varchar`, `uuid` | string |
| `boolean` | boolean |
| `json`, `jsonb` | map or list |
| `timestamptz` | `DateTime` in UTC, exact to the microsecond |
| `timestamp` | `NaiveDateTime` |
| `date`, `time` | `Date`, `Time` |
| `'infinity'` dates and timestamps | `:infinity` / `:"-infinity"` |
| arrays | lists |
| `NULL` | `nil` |

Column names come back as atom keys.

## Errors

Every call returns `{:ok, result}` or `{:error, message}`, where the message is the one Postgres wrote:

```elixir
{:error, "duplicate key value violates unique constraint \"users_email_key\""} =
  db(:users) |> insert(email: "taken@test.com") |> Moebius.Db.run()
```

Inside a transaction, a failed statement raises `Moebius.Error` so the transaction can roll back, and `transaction/1` turns it back into `{:error, message}`. If you rescue it yourself, it carries the SQLSTATE `code` and `name` (like `:unique_violation`), plus `detail`, `hint`, `constraint`, `table` and `column` when Postgres sends them.

## Safety

Every value you pass becomes a `$n` parameter; none are pasted into the SQL.

Table and function names, keyword column names, and atom column names are checked. Anything
that isn't a plain name (`users`, `membership.users`, `"Order Items"`) raises `ArgumentError`.
Sort directions, join types and document operators are checked against a list.

Strings supplied to `filter`, `select` (including strings in a column list), `sort`, `group`
and the column argument of `reduce` are **trusted SQL expressions**, used as written. Never
pass request input directly to these arguments. Map requested fields through an allowlist
of known columns; do not convert arbitrary request strings to atoms. Put user values in
parameters, for example `filter("price > $1", requested_price)`.

Parameters are also checked before they're sent. Moebius asks Postgres to parse the statement first, reads back the type it expects for each `$n`, and checks your values in your own process. A wrong type is a clear error and the connection stays up:

```elixir
{:error, "parameter $1 must be int4, got: \"five\""} =
  db(:users) |> filter(id: "five") |> Moebius.Db.run()
```

## Mix tasks

For setting up a database from SQL scripts (in the `scripts` directory):

```sh
mix moebius.create    # create the database
mix moebius.drop      # drop it
mix moebius.migrate   # run tables.sql (test env only)
mix moebius.seed      # run seeds.sql (test env only)
mix moebius.setup     # create + migrate + seed
mix moebius.reset     # drop + setup
```

None of them need `psql` installed.

## Contributing

Help is very welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for how to get the tests running and what a good pull request looks like. The short version: you need a local Postgres, and if you fix a bug, add a test that shows it.

```sh
mix deps.get
MIX_ENV=test mix moebius.setup
mix test
mix quality
```

The repo includes [Claude Code](https://claude.com/claude-code) skills in `.claude/skills/` (`erlang-otp`, `postgres-sql`, `elixir-testing` and `supabase-postgres-best-practices`). They're the rules the 5.0 code was held to, and they're a good read even if you don't use an AI assistant.

Found a security problem? Please report it privately; see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Copyright Rob Conery and Chase Pursley.
