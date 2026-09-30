---
name: postgres-sql
description: How Moebius writes SQL, and how to write SQL through Moebius that holds up at scale. Load BEFORE changing any function that builds a SQL string (lib/moebius/query.ex, query_filter.ex, document_query.ex, database.ex), before writing SQL files or DDL (test/db/*.sql, create_document_table), and when a user asks how to query, index, paginate, bulk load, search or run transactions well in Postgres. Complements supabase-postgres-best-practices (general rules with examples); this skill maps those rules onto Moebius's builders.
---

# Postgres through Moebius

For the general rules (with incorrect/correct SQL for each) read `../supabase-postgres-best-practices/references/`. The file names are prefixed by category: `query-`, `conn-`, `schema-`, `lock-`, `data-`, `monitor-`, `advanced-`. This skill covers what is specific to a query builder that concatenates SQL.

## 1. Values are parameters. Always.

Every value a caller supplies goes in `cmd.params` and appears in SQL as `$n`. No exceptions, including values that "can't" be hostile (integers, ids, JSON we encoded ourselves).

- Parameters are never parsed as SQL, so they can't inject. They also let Postgres reuse plans.
- `$n` numbering is shared across the whole command. A builder that appends a predicate numbers from `length(cmd.params) + 1`.
- JSON goes in as a parameter too: `body @> $1` with the map as the param. epgsql's JSON codec encodes it. An interpolated JSON literal breaks on the first `'` in the data and can be used for injection.
- `nil` in an equality filter means `IS NULL`, and it takes no parameter. (`col = NULL` is never true in SQL.)

## 2. Identifiers can't be parameters, so they are validated

Table and column names are interpolated. Anything interpolated must be proven safe first.

- Accept: `name`, `schema.name`, lower or upper case letters, digits, `_`, and a leading letter or `_`. Also accept a name that is already double-quoted, with no embedded quote.
- Reject everything else with `ArgumentError` **before** building SQL.
- Atoms are the normal way to pass identifiers (`db(:users)`, `sort(:name)`), and they must pass the same check. An atom can be created from user input.
- Sort directions are an allow-list: `:asc`, `:desc` (plus `nulls first/last` if supported). Anything else raises.
- Raw SQL fragments (`filter("price > $1", 10)`, `select("count(*) as n")`) are the caller's SQL on purpose and are passed through. Document them as "trusted input only".

## 3. Indexes decide everything at scale

A query is fast when it can use an index, so each builder should produce SQL an index can serve. (`query-missing-indexes.md`, `query-composite-indexes.md`, `query-partial-indexes.md`)

- `filter(email: x)` → `email = $1`. Needs a b-tree on `email` (a unique constraint creates one).
- `filter(:name, in: list)` → `name IN ($1, ...)`. Fine up to a few hundred values. Beyond that, `name = ANY($1)` with one array parameter keeps the statement text constant.
- Wrapping the column disables its index: `lower(email) = $1` needs an expression index `on users (lower(email))`.
- `LIKE 'abc%'` can use a b-tree with `text_pattern_ops`; `LIKE '%abc%'` cannot (use `pg_trgm` + GIN).

### Documents (JSONB)

The document table has `GIN (body jsonb_path_ops)`. (`advanced-jsonb-indexing.md`)

- `contains(k: v)` → `body @> $1`. **Uses the GIN index.** This is the fast path, and docs should steer users to it.
- `filter(:field, ">", v)` → `body -> 'field' > $1`. **Can't use** the GIN index. For hot fields, add an expression index: `create index on t ((body ->> 'field'))`, and compare with `->>` and a cast.
- `exists(:tags, "x")` → `body -> 'tags' ? $1`. `jsonb_path_ops` doesn't support `?`, so this is a scan. `contains(tags: ["x"])` does the same job and uses the index.
- `sort(:field)` → `order by body -> 'field'`. A scan plus a sort unless there's an expression index on that field.

### Full-text search

(`advanced-full-text-search.md`)

- Stored `search tsvector` with a GIN index is the fast path (`DocumentQuery.search/2`).
- On-the-fly `to_tsvector(concat(...)) @@ ...` scans the table. Fine for small tables, and the docs say so.
- `to_tsquery($1)` raises a syntax error on ordinary user input ("red shoes", "O'Brien"). `websearch_to_tsquery($1)` (Postgres 11+) accepts what people type into a search box. Prefer it for user-facing search.
- Pass the same text-search config to both sides (`to_tsvector('english', ...)` with `websearch_to_tsquery('english', $1)`), or neither.

## 4. Pagination

(`data-pagination.md`)

- `limit/offset` is fine for the first pages. At a large `offset`, Postgres reads and throws away every skipped row.
- For deep or infinite pagination, use **keyset**: `filter("id > $1", last_id) |> sort(:id) |> limit(50)`. Constant cost per page, given an index on the sort key.
- Always `sort` when you `limit`. Without `ORDER BY`, "the first 50" has no meaning and can change between runs.

## 5. Bulk writes

(`data-batch-inserts.md`)

- The protocol allows at most **65,535** parameters per statement. `bulk_insert` splits into commands of `div(max_params, column_count)` rows.
- Multi-row `VALUES` in batches of a few thousand rows is the sweet spot for a builder. Past that, `COPY FROM STDIN` is 5-10x faster. epgsql supports it (`copy_from_stdin`).
- Run the batches in one transaction (`transact_batch`) when the load should be all or nothing. Outside a transaction, each batch commits on its own.
- `insert ... on conflict (key) do update` for upserts (`data-upsert.md`). Never select-then-insert: that races.

## 6. Transactions: short, and nothing slow inside

(`lock-short-transactions.md`, `lock-deadlock-prevention.md`)

- A transaction holds a pooled connection and its row locks until it ends. No HTTP calls, no sleeps, no user waits inside `transaction/1`.
- After any error inside a transaction, Postgres rejects every further statement (`25P02`) until rollback. Moebius stops at the first error, rolls back, and returns `{:error, message}`.
- Touch rows in a consistent order (e.g. by primary key) when several transactions update overlapping rows. That avoids deadlocks.
- `select ... for update skip locked` turns a table into a job queue safely (`lock-skip-locked.md`).

## 7. Connections and timeouts

(`conn-pooling.md`, `conn-limits.md`, `conn-idle-timeout.md`)

- Each connection is a server process. A small pool (default 10) does more than a big one: past roughly `2 x cores` active queries on the server, throughput drops.
- Put a ceiling on every query on the server side: `statement_timeout` (Moebius sets it per connection from config). epgsql calls wait forever otherwise.
- `idle_in_transaction_session_timeout` protects the server from a client that opened a transaction and wandered off.
- Set `application_name`, so `pg_stat_activity` shows who is connected.

## 8. DDL Moebius generates

- New document tables: `id bigint generated by default as identity primary key`. `serial` is legacy, and `integer` ids run out at 2.1 billion (`schema-primary-keys.md`).
- `created_at`/`updated_at` are `timestamptz not null default now()` (`schema-data-types.md`).
- Index names are derived from the table name. Postgres truncates identifiers at 63 bytes, so long table names can collide. Keep derived names short.
- Use `create table if not exists` and `create index if not exists`, so two processes racing to auto-create the same document table don't error.

## 9. Find out, don't guess

(`monitor-explain-analyze.md`, `monitor-pg-stat-statements.md`)

```sql
explain (analyze, buffers) <the query Moebius built>;
```

- `Seq Scan` on a big table in a hot path = missing or unusable index.
- `rows=` estimate far from `actual rows=` = stale stats. Run `analyze t`.
- `pg_stat_statements` ranks queries by total time. Fix the top five and stop.

## Checklist for a builder change

- [ ] Every caller value is a `$n` parameter, numbered after existing params.
- [ ] Every interpolated identifier goes through validation; directions and operators are allow-listed.
- [ ] The generated SQL for the common case can use an index; if it can't, the docs say so and name the index that would help.
- [ ] `limit` without `sort` is called out in the docs.
- [ ] Builder test pins the exact SQL and params; a round-trip test runs it.
