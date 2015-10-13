# Moebius

A functional query tool for Elixir and PostgreSQL.


Things to do ...

 - [ ] Create a todo list

## Target API Experience

Thought I would lay this out here, now, mostly so I don't forget :p. I'm after elegance, of a functional sort. Something that just sits nicely right behind your eyes and makes you breath in... deeply ... and say "yeahhhhh". Ideally...

```
table :users
  |> filter email: "test@test.com"
  |> order_by :last
  |> first_result
```

It feels... right. We can take this experience and move it all over the place...

```
table :users
  |> insert email: new_email, first: "blah", last: "blah"
  |> table :logs
  |> update entry: "New user added #{new_email}"
```

I love the idea of constructing query calls with a pipe. Yeah, I said it.

## CTEs

One thing I think would be fascinating is to try and construct a query on the fly with a CTE; something we build as we go. This is ... kind of bonkers to think on, but it might be possible.

## Schema As We Go

Building tables, views, functions etc as we go along. Versioning, diffing - I want this to be a "roundtrip" kind of tool that *loves* SQL and helps you write it and execute it.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add moebius to your list of dependencies in `mix.exs`:

        def deps do
          [{:moebius, "~> 0.0.1"}]
        end

  2. Ensure moebius is started before your application:

        def application do
          [applications: [:moebius]]
        end
