# pooler, as Moebius uses it

pooler 1.x (Apache-2.0), maintained in the epgsql org. Zero dependencies. Source: https://github.com/epgsql/pooler

## The model

- A pool is a gen_server plus supervisors for its members. Members are started by `start_mfa`, e.g. `{:epgsql, :connect, [opts]}`.
- `take_member` gives the calling process **exclusive** use of one member. pooler monitors the caller: if it dies, the member is killed and replaced (it may be mid-query).
- Members are `temporary`. A crashed member is replaced; a failed start is logged and retried later. The pool never restarts because the database is down; callers get `:error_no_members`.

## Starting a pool inside the user's tree

Don't rely on the `:pooler` application env. Moebius builds the config and asks pooler for a child spec, so the pool lives in the user's supervision tree:

```elixir
config = %{
  name: MyApp.Db,                         # pool name (an atom); Moebius uses the Db module
  init_count: 2,                          # connections opened at start
  max_count: 10,                          # the ceiling
  start_mfa: {:epgsql, :connect, [conn_opts]},
  queue_max: 50,                          # callers allowed to wait when the pool is busy
  cull_interval: {1, :min},               # shrink back toward init_count after bursts
  max_age: {5, :min},
  member_start_timeout: {10, :sec},
  max_lifetime: {30, :min},               # recycle before firewalls/proxies kill idle TCP
  max_lifetime_jitter: {2, :min}
}

:pooler.pool_child_spec(config)
```

- `:pooler` must be **started as an application** (it owns a group table and a supervisor). It is listed as a dependency, so Mix starts it automatically with the user's app. `pool_child_spec/1` gives a child spec that runs under **our** supervisor.
- `pool_child_spec/1` checks the config at start. A bad key or a bad time spec is an error from `start_link`, not a later surprise.
- Time specs: `{n, :min}`, `{n, :sec}`, `{n, :ms}`, `{n, :hour}`, or a plain integer in ms.

## Checkout

```elixir
case :pooler.take_member(pool, {5, :sec}) do
  :error_no_members -> {:error, :pool_timeout}
  conn when is_pid(conn) ->
    try do
      fun.(conn)
    after
      :pooler.return_member(pool, conn, status)   # :ok or :fail
    end
end
```

- `take_member/1` never waits. `take_member/2` queues up to `queue_max` callers; beyond that, or after the timeout, it returns `:error_no_members`.
- `return_member(pool, pid, :fail)` kills the member and starts a new one. Use it when the connection's state is unknown (socket error, a transaction we couldn't roll back, a cancelled query).
- Return in `after`, always. A leaked member stays checked out until the caller process exits.
- The process that takes the member must be the one that uses it.

## Sizing

- Postgres runs a process per connection (several MB each), and throughput peaks at a fairly small number of active connections. The old rule of thumb is `(cores * 2) + effective_spindles` on the **database** server, across **all** app nodes combined.
- Default Moebius pool: `init_count: 2`, `max_count: 10`. Most apps never need more. If a pool is often at `max_count`, look for slow queries and long transactions before raising it.
- Behind PgBouncer in transaction mode: named prepared statements break. Moebius uses the unnamed statement (`equery`), which is fine.

## Observability

- `:pooler.pool_utilization(pool)` gives `max_count`, `in_use_count`, `free_count`, `starting_count`, `queued_count` and `queue_max`. Moebius exposes this as `MyApp.Db.pool_status/0`.
- `:pooler.pool_stats(pool)` lists each member with its state.
