# Phase 1 Plan: Build on Current Tooling

Goal: Moebius builds, tests and passes the quality checks on Elixir 1.20 / OTP 29, with **no public API changes**.
Scope limit: **postgrex stays at 0.19.2** (no driver changes in this phase).

Verify with:
`MIX_ENV=test mix moebius.migrate && MIX_ENV=test mix moebius.seed && mix test && mix quality --strict`

## Tasks

- [x] **1. Toolchain pin.** Set `.tool-versions` to `erlang 29.0.5` / `elixir 1.20.4-otp-29` (matches the local machine; CI reads this file).
- [x] **2. Dev/test deps.** `credo ~> 1.7` (1.7.8 doesn't compile on 1.20), `sobelow ~> 0.15`, `ex_doc ~> 0.40`. Loosen `jason` to `~> 1.4`. Leave `postgrex` alone.
- [x] **3. Transitive security fix.** ⚠️ *Partial.* decimal 2.1.1 → 2.4.1, but the CVE-2026-32686 fix is only in decimal **3.0+**, and postgrex 0.19.2 caps it at `~> 2.0`. Still open, and moved to Deferred.
- [x] **4. mix.exs cleanup.** Remove the deprecated `build_embedded`. Keep `elixir: "~> 1.15"` so library users aren't forced to upgrade.
- [x] **5. Config.** Add an empty `config/prod.exs` so `MIX_ENV=prod` can load config.
- [x] **6. Compiler warnings in `lib/`.** Change nothing's behavior:
  - [x] `transformer.ex`: `List.zip/1` → `Enum.zip/1`
  - [x] `query_filter.ex`: remove the redundant `filter/3` clause (line 225)
  - [x] `database.ex`: remove unreachable `update_search/2` clause(s) and the dead `{:error, _}` branch in `create_document_table/1`; replace always-true `a && b` chains with sequential calls
  - [x] `postgrex_types.ex` BitString warning: it comes from postgrex 0.19's generated code, so **it can't be fixed without upgrading the driver**. It blocked `--warnings-as-errors`, so CI now fails only on warnings that point at `lib/` (see task 8).
- [x] **7. Quality checks.** Get `mix format --check-formatted`, `sobelow`, and `credo --only warning` passing under the newer versions.
- [x] **8. CI.** `actions/checkout@v4`, `actions/cache@v4`. The "Check warnings" step now runs `mix deps.compile`, then `mix compile --force` into a log, and fails if any warning points at `lib/`.
- [x] **9. Full verification.** Run the verify line above; all 104 tests pass.
- [x] **10. Docs.** Update `PROJECT.md` "Current state", and refresh `.codemap`.

## Deferred (not this phase)

- postgrex 0.19.2 → 0.22.x. **CVE-2026-32687 (HIGH) and CVE-2026-58225 (LOW) stay open** until the driver is upgraded. Both are in `Postgrex.Notifications`, which Moebius doesn't use, but anything that depends on it still pulls them in.
- decimal → 3.x (CVE-2026-32686, MEDIUM). This needs a postgrex version that allows decimal 3.
- The compiler warning from postgrex's BitString code goes away with the driver upgrade. After that, CI can go back to plain `mix compile --warnings-as-errors`.
- Watch out: `mix deps.update --all` moves postgrex to 0.19.3 and db_connection to 2.10.2 (both within the current `~>` ranges). Update named deps only until the driver phase.
- SQL injection fixes, transaction/ROLLBACK rework, dead-code removal (phase 2).

## Log

2026-09-30. All tasks done. Verify line passes: **104 tests passed**, `mix quality --strict` is clean, and `MIX_ENV=prod mix compile` works.

- Locked deps: credo 1.7.8→1.7.19, sobelow 0.13.0→0.15.0, ex_doc 0.34.2→0.40.4, jason 1.4.4→1.4.5, decimal 2.1.1→2.4.1 (plus ex_doc's makeup/earmark deps). postgrex 0.19.2, db_connection 2.7.0 and telemetry 1.3.0 are **unchanged**.
- `lib/` edits keep the existing behavior: `Enum.zip/2`; removed an unreachable `filter/3` clause and 2 unreachable `update_search/2` clauses; removed the dead `{:error, _}` branch in `create_document_table/1`; split `a && b` chains into sequential calls (the left side was always truthy); `length(x) > 0` → `x != []` (credo 1.7.19 flags this; the change was also made in 8 test assertions).
- The 3 logged `transaction is not started` errors during tests are still there (phase 2: ROLLBACK rework).
- CI hasn't run yet. The setup-beam pins (`erlang 29.0.5`, `elixir 1.20.4-otp-29`) get confirmed on the first push.
