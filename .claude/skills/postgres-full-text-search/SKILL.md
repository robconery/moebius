---
name: postgres-full-text-search
description: Rob's rules for Postgres full-text search, with an English dictionary for prose and a simple dictionary for literal values (names, tags, cities, countries, codes), concatenated in both the tsvector and the tsquery. Every search is ranked, exact literal matches rank above stemmed matches, and results come back in descending rank order. Load BEFORE writing or changing anything that uses tsvector, tsquery, to_tsvector, websearch_to_tsquery, ts_rank, ts_headline, a search column or a GIN text-search index, and whenever someone asks how to add search to a table. Takes precedence over supabase-postgres-best-practices/references/advanced-full-text-search.md.
---

# Postgres full-text search: English + simple

This skill **supersedes** `supabase-postgres-best-practices/references/advanced-full-text-search.md`. Where they disagree, follow this one.

Source: PostgreSQL docs, chapter 12 (textsearch-controls, textsearch-tables, textsearch-dictionaries) and section 9.13 (text search functions). The behavior below was checked on Postgres 17.

## The core rule

Use two text-search configurations and concatenate them:

| Kind of text | Examples | Config |
|---|---|---|
| Prose, a large corpus | body, description, comments, notes | `english` |
| Literal values | names, tags, locations, cities, countries, SKUs, brands, usernames | `simple` **and** `english` |

- `english` stems words and drops stop words: `Paris` → `'pari'`, `running` → `'run'`, `The Who` → nothing.
- `simple` only lowercases: `Paris` → `'paris'`, `The Who` → `'the' 'who'`. It has no stop words and does no stemming.
- Concatenate both into **one** `tsvector` with `||`, and OR both queries together with `||`. Do this on both sides, always.

### Why literal fields get both, not only `simple`

One search box covers every field. The query is OR'd as `english(q) || simple(q)`, and each branch has to match the whole query on its own:

```
websearch_to_tsquery('english','hotels in paris') || websearch_to_tsquery('simple','hotels in paris')
→ 'hotel' & 'pari' | 'hotels' & 'in' & 'paris'
```

If `city` were indexed as `simple` only, the vector would hold `'hotel'` (from the English body) and `'paris'` (from the simple city). The English branch needs `'pari'`, and the simple branch needs `'hotels'` and `'in'`. **Neither branch matches** (verified). With `city` indexed as both `english` and `simple`, the English branch matches, and the simple branch still catches literals that English would destroy (`The Who`, `IT`, `US`, `Will`).

Prose stays `english` only. Adding `simple` to a large body roughly doubles the vector and index for little gain.

## Weights carry the ranking scheme

A lexeme in a `tsvector` doesn't record which config produced it: `honolulu` from `simple` and `honolulu` from `english` are the same lexeme. **The weight label is the only way to tell an exact literal from a stem or a word in the prose**, so the weights are fixed:

| Weight | Content | Config | Meaning |
|---|---|---|---|
| **A** | literal fields | `simple` | exact literal value. **Reserved for this. Nothing else gets A.** |
| **B** | title | `english` | strong prose |
| **C** | literal fields | `english` | stemmed literal |
| **D** | body | `english` | prose |

## The pattern: a stored generated column

```sql
-- array_to_string, concat and concat_ws are STABLE, not IMMUTABLE, so a
-- generated column rejects them ("generation expression is not immutable").
-- Wrap them once:
create function text_search_join(text[]) returns text
  language sql immutable parallel safe
  as $$ select array_to_string($1, ' ') $$;

alter table articles add column search tsvector generated always as (
    setweight(to_tsvector('simple',  coalesce(author, '') || ' ' || coalesce(city, '') || ' ' || coalesce(country, '') || ' ' || coalesce(text_search_join(tags), '')), 'A')
 || setweight(to_tsvector('english', coalesce(title, '')), 'B')
 || setweight(to_tsvector('english', coalesce(author, '') || ' ' || coalesce(city, '') || ' ' || coalesce(country, '') || ' ' || coalesce(text_search_join(tags), '')), 'C')
 || setweight(to_tsvector('english', coalesce(body, '')), 'D')
) stored;

create index articles_search_idx on articles using gin (search);
```

Rules that apply to it:

- **Always use the two-argument `to_tsvector('english', ...)` / `to_tsvector('simple', ...)`.** The one-argument form depends on `default_text_search_config`, is only `STABLE`, and can't be used in a generated column or an expression index. The docs say an index on it "might be inconsistent" and couldn't be dumped and restored correctly.
- **`coalesce` every column.** `to_tsvector(NULL)` is NULL, and `NULL || vector` is NULL, so one null field blanks the whole row's search.
- **Join with `||`, not with `concat`, `concat_ws` or `format`.** Those are STABLE (verified with `pg_proc.provolatile`).
- **Arrays:** use an immutable wrapper as shown above, then `to_tsvector('simple', ...)`. `array_to_tsvector(tags)` is immutable but uses the strings "as-is, without further processing": it doesn't lowercase or split, so `'New York'` becomes one lexeme that never matches a query. Don't use it for user-entered tags.
- **Weights:** follow the table above. If a title is really a literal (a product name, a city name), put it in the literal group, not in B.
- **Use a generated column over an expression index.** The column means queries don't need to repeat the exact expression to hit the index. An expression index saves disk, but every query must match its expression character for character, configs included.
- Position shifts: `||` offsets the right side's positions past the left side's, so field order is stable. Phrase queries (`"..."`, `<->`) can match across a field boundary. Accept that or put a separator field between them.
- Older tables, or logic that can't be immutable (lookups from other tables): use a `BEFORE INSERT OR UPDATE` trigger that sets `search` the same way. Never compute it in application code.

## The query: always ranked, always descending

Every search returns a rank and is sorted by it, descending. There is no unranked search.

Two scores:

1. **`literal_rank`**: how well the query's words hit **weight A** (exact literals). The weight array `'{0,0,0,1}'` (order `{D,C,B,A}`) zeroes every other weight, so only exact literal hits count.
2. **`rank`**: overall relevance across all weights (default `{0.1, 0.2, 0.4, 1.0}`).

Sort by `literal_rank desc, rank desc`. Any row with an exact literal hit comes before every row that only matched a stem or the prose. Ties fall back to relevance.

The literal score needs the query's words **OR'd**: `websearch_to_tsquery` ANDs them, so for `hotels in honolulu` it would require `hotels`, `in` and `honolulu` all to be literals, and the score drops to ~0. Create this helper once:

```sql
-- Every word of the input, lowercased by the simple config, OR'd together.
-- quote_literal keeps tsquery operators in user input (: & | !) from being parsed.
create function text_search_literal_query(text) returns tsquery
  language sql immutable parallel safe
  as $$
    select to_tsquery('simple', coalesce(string_agg(quote_literal(lexeme), ' | '), ''))
    from unnest(to_tsvector('simple', coalesce($1, '')))
  $$;
-- 'hotels in honolulu' -> 'honolulu' | 'hotels' | 'in'
```

The canonical search query:

```sql
select id, title,
       ts_rank('{0,0,0,1}', search, lq) as literal_rank,
       ts_rank(search, q)               as rank
from articles,
     lateral (select websearch_to_tsquery('english', $1)
                  || websearch_to_tsquery('simple',  $1)  as q,
                     text_search_literal_query($1)        as lq) query
where search @@ q
order by literal_rank desc, rank desc
limit 20;
```

Verified (city `Honolulu` in row 2, `Honolulu` only in title or body elsewhere):

| query | order |
|---|---|
| `honolulu` | city = Honolulu (literal 0.61) › title "Hotels in Honolulu" › title "Honolulu nights" › body mention |
| `hotels in honolulu` | city = Honolulu (literal 0.20) › title "Hotels in Honolulu" (literal 0) |
| `running` | tag `running` (literal 0.61) › tag `runs` / body `run` (stem only) |

Rules:

- **`q` filters and `lq` only scores.** `lq` ignores phrases and `-exclusions`, which is fine because `q` has already applied them in the `WHERE`.
- **Use `websearch_to_tsquery` for the filter.** It "will never raise syntax errors", and it supports `"quoted phrases"`, `or` and `-exclude`. `to_tsquery` raises on ordinary input such as `red shoes` or `O'Brien`. Keep `to_tsquery` for queries the application builds itself.
- **Pass the user text once as a parameter (`$1`).** Never interpolate it.
- `tsquery || tsquery` is OR and `&&` is AND. The filter wants `||`, because either interpretation of the query may match.
- The GIN index is still used (verified: Bitmap Index Scan on `search`). The two ranks are computed only for the matching rows, then sorted.
- A query made only of English stop words (`the who`) gives an empty English branch with a NOTICE. The simple branch still finds `The Who`, and it scores as a literal.
- Prefix or type-ahead search on names and tags: `to_tsquery('simple', $1 || ':*')`, after removing tsquery operators from the input, or use `pg_trgm`. Don't stem a prefix. Rank and sort these results the same way.

## Ranking and highlighting

- Ranking reads the vector of every matching row, so it's expensive on broad queries. Keep the `LIMIT`, and paginate with keyset pagination on `(literal_rank, rank, id)`, not with deep `OFFSET`.
- `ts_rank` scores term frequency. `ts_rank_cd` also rewards terms that appear close together: you can use it for `rank`, but keep `literal_rank` on `ts_rank`. Normalization `1` (divides by 1 + log of document length) stops long bodies from crowding out short rows. `32` only rescales the score and doesn't change the order.
- If one number is needed (an API response, for example), return both columns anyway. Folding them into one score breaks the rule that literals come first.
- `ts_headline('english', body, q)` works on the **raw text**, not the vector. It's slow, so run it only on the final page of results. Its output is **not HTML-safe**: sanitize it, or strip markup from the input first.
- Use `english` in `ts_headline` for prose fields, and `simple` when highlighting a literal field.

## Accents (optional)

Names and places often carry accents (`José`, `Zürich`). If users will type them without accents, build a config with the `unaccent` extension and use it in place of `simple` (and, if needed, `english`) on **both** sides:

```sql
create extension if not exists unaccent;
create text search configuration simple_unaccent (copy = simple);
alter text search configuration simple_unaccent
  alter mapping for hword, hword_part, word with unaccent, simple;
```

Swap it in everywhere `simple` appears: the A-weight vector, the `simple` branch of the filter, **and** `text_search_literal_query`, or literal hits stop matching. Changing a config means rebuilding the stored column, so pick it up front.

## Checklist

- [ ] Prose uses `english` only. Literal fields use `english` **and** `simple`.
- [ ] Every `to_tsvector` / `*_to_tsquery` call names its config.
- [ ] Every column is wrapped in `coalesce(col, '')`. No `concat`/`concat_ws`/`array_to_string` directly in a generated column.
- [ ] Weights: A = `simple` literals (only), B = title, C = `english` literals, D = body.
- [ ] A stored generated `tsvector` column with a GIN index.
- [ ] The filter is `websearch_to_tsquery('english', $1) || websearch_to_tsquery('simple', $1)`, with the user text as a parameter.
- [ ] Every search selects `literal_rank` (`ts_rank('{0,0,0,1}', search, text_search_literal_query($1))`) and `rank`, and has `order by literal_rank desc, rank desc`.
- [ ] `EXPLAIN` shows a Bitmap Index Scan on the GIN index.
- [ ] `ts_headline` runs only on returned rows, and its output is sanitized.

## References

- https://www.postgresql.org/docs/current/textsearch-controls.html
- https://www.postgresql.org/docs/current/textsearch-tables.html
- https://www.postgresql.org/docs/current/textsearch-dictionaries.html
- https://www.postgresql.org/docs/current/functions-textsearch.html
- https://www.postgresql.org/docs/current/unaccent.html
