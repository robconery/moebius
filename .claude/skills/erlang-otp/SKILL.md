---
name: erlang-otp
description: OTP design rules for Moebius, an Elixir library that runs on Erlang's epgsql driver and pooler connection pool. Load BEFORE writing or changing any code that starts, owns, supervises, links, monitors or messages a process; that checks connections in or out of a pool; that calls an Erlang module from Elixir (epgsql, pooler, :queue, :ets and so on); that handles Erlang records, charlists or error tuples; or that reads application config. Also load when debugging hangs, leaked connections, "no members" errors, mailbox growth, crashes that take down a supervisor, or anything that behaves differently under concurrency.
---

# Erlang / OTP for Moebius

Moebius is a **library**. Its users put it inside their own supervision trees, next to code we will never see. Everything below follows from that: we must be a good tenant in someone else's BEAM node.

The rules are ordered by how much damage breaking them does.

## 1. Every process has a supervisor and an owner

- Nothing Moebius starts may be orphaned. A process is started with `start_link` from a supervisor child spec, or it is owned by a process that is.
- A library does not start global processes behind the user's back. The user adds `{MyApp.Db, opts}` to their tree; our `child_spec/1` describes what gets started. If Moebius ships an OTP application callback, it must be declared in `mix.exs` (`mod:`), and it must start nothing unless config asks for it.
- The pool is the unit of supervision, not the connection. A pool of N connections is **one** child in the user's tree (a supervisor that owns the pool), so a database outage is contained inside it.

## 2. External resources going away is not a bug

"Let it crash" is for bugs. A database that is restarting, a network blip or a full connection limit are not bugs, and must not cascade into restarts of the user's app.

- Connection workers are `temporary` inside the pool. The pool replaces them. The pool itself stays up while the database is down and returns an error (`error_no_members`) to callers instead.
- Callers get `{:error, reason}` for database trouble, never an exit from a linked process that took their process down with it.
- Reconnect with backoff (pooler does this for us: failed starts are retried when demand arrives or the pool is refilled).

## 3. Exclusive ownership of a connection

An epgsql connection is a single process with a single socket. Two processes using it at the same time interleave protocol messages (epgsql uses the **unnamed** prepared statement by default, which is shared per connection).

- Check a connection out, use it, check it back in, **in the same process**. pooler monitors the process that called `take_member`; handing the pid to another process defeats that.
- Always return it in an `after` block, so an exception can't leak it:

```elixir
conn = :pooler.take_member(pool, timeout)
try do
  fun.(conn)
after
  :pooler.return_member(pool, conn, status)
end
```

- Return with `:fail` (not `:ok`) when you can't trust the connection's state: a socket error, a timeout, a transaction you could not roll back. pooler then kills it and starts a fresh one. Returning a poisoned connection with `:ok` hands the problem to the next caller.
- A transaction pins one connection for its whole duration. Code inside the transaction must use that connection, not check out another one (that would run outside the transaction and can deadlock the pool).
- Nesting: if the current process already holds a connection (for example, inside a transaction), reuse it. Keep that in the process dictionary under a key scoped to the pool, and clear it in `after`.

See `references/pooler.md` for the configuration we use and why.

## 4. Every wait has a timeout, and it is chosen, not defaulted

- `:pooler.take_member/2` gets an explicit timeout (queueing). `take_member/1` never waits and fails immediately when the pool is busy, which is almost never what a web request wants.
- Long-running SQL is bounded on the **server** with `statement_timeout`, not by killing the client process. Killing a process mid-query leaves the socket in an unknown protocol state; that connection must then be discarded (`:fail`).
- `GenServer.call/3` defaults to 5 s. If you wrap something slower in a call, pass a timeout and document it.

## 5. Tagged tuples at the boundary, exceptions for bugs

- The public API returns `{:ok, value}` or `{:error, reason}` for anything the database can cause (constraint violations, missing tables, bad SQL the user wrote).
- Raise for programmer errors we can detect before touching the database: a bad identifier, an empty insert, a wrong argument type. `ArgumentError` with a clear message.
- Never `raise` a string built from a database error inside library code just to `catch` it one frame up. Use the tuple.
- Never swallow `:exit` or `:throw` wholesale with `catch _, _`. Match what you expect; let the rest crash.

## 6. Erlang interop from Elixir

- **Records.** epgsql returns records (`#column{}`, `#error{}`, `#statement{}`). Use `Record.extract/2` so field order comes from the header, not our guess:

```elixir
require Record
Record.defrecordp(:pg_error, :error, Record.extract(:error, from_lib: "epgsql/include/epgsql.hrl"))
Record.defrecordp(:pg_column, :column, Record.extract(:column, from_lib: "epgsql/include/epgsql.hrl"))
```

- **Strings.** Erlang "strings" are charlists. epgsql accepts `iodata()` for SQL and binaries for text parameters, so send binaries. Text comes back as binaries.
- **Null.** epgsql's default null term is the atom `null` (and it also accepts `undefined`). Configure `nulls: [nil, :null]` on connect so Elixir `nil` goes in and comes out as `nil`, with no translation layer.
- **Maps vs proplists.** epgsql's `connect/1` takes a map. Build it from keyword config explicitly; don't pass user keywords through unfiltered (unknown keys are silently ignored, which hides typos).
- **Atoms are never garbage-collected.** Never `String.to_atom/1` on data that comes from outside the code: user input, JSON keys from an unknown document, or column names from arbitrary SQL. Column names from our own tables are a bounded set, but `run("select ...")` accepts any SQL, so prefer `String.to_existing_atom/1` with a fallback, or document the risk.

## 7. Configuration is read at runtime

- Read `Application.get_env/2` inside functions (at start time), never in a module body. A module body runs at **compile** time, so the value gets frozen into the `.beam` and a release config change is silently ignored.
- Accept options as arguments first (`start_link(opts)`), fall back to app env second. Libraries should work with no app env at all.
- Validate options once, at start, with a clear error. `Keyword.validate!/2` is good for this.

## 8. Mailboxes

- A process that receives messages it never matches grows until the node dies. epgsql sends notices and `LISTEN/NOTIFY` messages to the `async` pid if one is configured; we don't configure one, so they are dropped.
- Don't leave `receive` without an `after` clause in library code.
- Large results are copied between processes. The epgsql connection process decodes rows, then sends them to the caller. That is fine for normal queries; for very large exports, stream with `epgsqli` or use a cursor.

## 9. Observability

- Log at the boundary, once, with the error and a short context. Don't log and also return the error to be logged again by the caller.
- `Logger` metadata over string interpolation.
- Tests should be quiet. An expected error in a test goes through `ExUnit.CaptureLog`.

## Checklist before you commit OTP code

- [ ] Every started process is linked to a supervisor or an owner that is.
- [ ] A dead database returns `{:error, _}` to callers and restarts nothing outside the pool.
- [ ] Every checkout has a matching return in `after`, with `:fail` on unknown state.
- [ ] Every blocking call has a deliberate timeout.
- [ ] No `Application.get_env` in a module body.
- [ ] No `String.to_atom` on outside data.
- [ ] Records come from `Record.extract`, not hand-written tuples.

## References

- `references/epgsql.md`: the epgsql API, result shapes, types and gotchas, as used here.
- `references/pooler.md`: pooler configuration and checkout semantics.
- OTP Design Principles: https://www.erlang.org/doc/system/design_principles.html
- Supervisor behaviour and child specs: https://www.erlang.org/doc/apps/stdlib/supervisor.html
- Elixir library guidelines: https://hexdocs.pm/elixir/library-guidelines.html
- Process anti-patterns: https://hexdocs.pm/elixir/process-anti-patterns.html
