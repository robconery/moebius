---
name: elixir-testing
description: ExUnit standards for Moebius. Load BEFORE writing, changing or reviewing any file under test/, adding a doctest, changing test_helper.exs or test fixtures (test/db/*.sql), or when a test is flaky, slow, noisy or order-dependent. Also load when finishing any lib/ change, to decide which tests it needs. Covers test isolation against a shared Postgres database, assertion style, naming, doctests, logging noise, regression tests, and the checklist a test file must pass.
---

# Testing Moebius

Moebius builds SQL and runs it. So there are two kinds of test, and a feature usually needs both:

1. **Builder tests** check the SQL string and params a pipeline produces. No database. Fast, exact, and they document the public API.
2. **Round-trip tests** run the command against Postgres through `TestDb` and check what came back. They catch everything the string can't: types, NULLs, driver behaviour, transactions.

A builder test proves we *asked* for the right thing. A round-trip test proves we *got* it. Ship neither alone for anything that touches the driver.

## 1. Every test owns its data

The suite shares one database. A test that passes alone and fails in the full run is a bug in the test.

- **Set up what you read.** If a test asserts on a row, that test (or its `setup`) created the row. Never rely on `seeds.sql` rows, on another module's inserts, or on `id == 1`.
- **Reset what you touch.** `setup` clears the tables the module writes to. Prefer `truncate ... restart identity cascade`: it resets sequences and gives a clean heap (after a `DELETE`, Postgres may return rows in any order).
- **Use unique values.** When a test needs a unique column (the `users.email` constraint), make the value unique to that test: `"find-#{System.unique_integer([:positive])}@test.com"`.
- **Never depend on row order without `ORDER BY`.** If the builder under test has no sort, assert on membership, not position.
- **`async: false` is the default and stays that way** for any module that touches the database (they share tables). Pure builder test modules can and should be `async: true`.
- `setup_all` is for read-only fixtures. Data a test mutates belongs in `setup`.

Check isolation before you push:

```sh
mix test --seed 0 && mix test && mix test --repeat-until-failure 20
```

## 2. Assert the shape, not the truthiness

Weak assertions hide regressions. Pattern-match the value you expect.

| Weak | Strong |
|---|---|
| `assert res != []` | `assert [_ | _] = res` or `assert [%{email: "a@b.com"}] = res` |
| `assert res` | `assert %{id: id} = res` and `assert is_integer(id)` |
| `assert res.deleted` | `assert {:ok, %{deleted: 1}} = ...` |
| `assert length(cmd.params) == 2` | `assert cmd.params == [1, "a@b.com"]` |
| `{:ok, res} = ...` then `assert res.x == 1` | `assert {:ok, %{x: 1}} = ...` (the failure message shows the whole value) |
| `case r do {:error, e} -> raise e; {:ok, v} -> assert ... end` | `assert {:ok, v} = r` |
| `assert {:error, _} = ...` | `assert {:error, "duplicate key value violates unique constraint" <> _} = ...` (pin the part that proves *which* error; the message string is Moebius's public error API) |

- Use `assert x == expected` (not `assert expected == x`). ExUnit labels the left side as the value under test.
- Every `test` has at least one assertion. A test that only runs code proves only that it didn't raise; if that is the point, say so with `assert {:ok, _} = ...`.
- For floats, `assert_in_delta`.
- For exceptions, `assert_raise ArgumentError, ~r/bad identifier/, fn -> ... end`.

## 3. Structure and naming

- Module: `Moebius.<Thing>Test`, file `test/moebius/<thing>_test.exs`. One module per file.
- `describe "function_name/arity"` or `describe "<behaviour>"`. The test name finishes the sentence: `test "returns nil when no row matches"`.
- Arrange / act / assert, in that order, separated by a blank line when the test is longer than a few lines.
- Helpers that build data go at the bottom as `defp`, or in `test/support/` if more than one module uses them.
- Regression tests reference the issue: `test "filter(col: nil) matches NULL (#35)"`.

## 4. No dead tests

- No commented-out tests. Either fix it, delete it, or `@tag :skip` with a comment giving the reason and the issue link.
- No commented-out code inside tests.
- Doctests run. If a module has `iex>` examples, the test file says `doctest Module`, and the examples are correct. A wrong doctest is worse than none because it teaches the wrong API.

## 5. Quiet, fast, deterministic

- The suite prints nothing but dots. Expected errors are captured: `capture_log(fn -> ... end)` and assert on the log if it matters.
- No `Process.sleep/1` to wait for something. Use `assert_receive msg, timeout` or poll with a bound.
- No real clock in assertions. Compare to a value you control, or assert a range.
- Randomness is seeded by ExUnit. If you need random data, use `:rand` after ExUnit's seed, so `--seed` reproduces it.

## 6. Test data is professional

This is a published package; the test folder ships in the Hex tarball. Test data uses neutral names and values.

## 7. What a change needs

| Change | Tests |
|---|---|
| New builder function or option | builder test for the SQL and params, plus one round-trip |
| Driver, type or result-shape change | round-trip tests for each Postgres type touched, NULL included, both directions (as a param and as a result) |
| Bug fix | a failing test first, named for the bug, then the fix |
| Anything touching transactions | commit path, rollback-on-error path, rollback-on-raise path, and "the connection is usable afterwards" |
| Anything touching the pool | checkout returned after success, after an error and after a raise; behaviour when the pool is exhausted |
| Security fix (injection) | a test that the hostile input is sent as a parameter or rejected, never executed |

## 8. The database for tests

- `MIX_ENV=test mix moebius.migrate` rebuilds the schema from `test/db/tables.sql`; `mix moebius.seed` loads `seeds.sql`. Tests must pass on a freshly migrated database **and** after the suite has already run once.
- Tables created by a test (`drop table if exists x; create table x ...`) use a name no other module uses.
- Document tables auto-create on first save. Tests that depend on that drop the table first.

## Checklist for a test file

- [ ] Module and file names follow `Moebius.XTest` / `x_test.exs`.
- [ ] `async: true` if and only if it never touches the database.
- [ ] Every test creates the rows it asserts on; no dependency on seeds, ids or other modules.
- [ ] No positional assertions on unsorted queries.
- [ ] Every test asserts a specific shape or value.
- [ ] No commented-out tests or code; doctests enabled and correct.
- [ ] Silent run: expected errors captured.
- [ ] Passes with `--seed 0`, a random seed, and `--repeat-until-failure 20`.

## References

- ExUnit: https://hexdocs.pm/ex_unit/ExUnit.html
- ExUnit.Case (async, describe, tags): https://hexdocs.pm/ex_unit/ExUnit.Case.html
- ExUnit.CaptureLog: https://hexdocs.pm/ex_unit/ExUnit.CaptureLog.html
- Doctests: https://hexdocs.pm/ex_unit/ExUnit.DocTest.html
- Elixir anti-patterns (code, design, process): https://hexdocs.pm/elixir/what-anti-patterns.html
