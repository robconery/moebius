![travis](https://travis-ci.org/robconery/moebius.svg?branch=master) [![Hex.pm Version](https://img.shields.io/hexpm/v/moebius.svg)](https://hex.pm/packages/moebius)

# Moebius: A functional query tool for Elixir and PostgreSQL.

I love working with Elixir but so far there hasn't been all that much choice when working with a database. Ecto works very well, but to me ORMs are just a bit out of place in the functional landscape of Elixir. I wanted to explore some options, so I made this package.

*Please note*: This started as a bit of a "spike", if you will. [I mentioned on the ElixirFountain podcast](https://soundcloud.com/elixirfountain/elixir-fountain-2015-10-16-rob-conery) that there were approaches and concepts in Ecto that I found a bit confusing. Namely:

 - An object-oriented concept in a functional language
 - A generic "Repository" interface (CRUD ops) that [isn't really a Repository](http://martinfowler.com/eaaCatalog/repository.html) which is OK, it's just a bit confusing.
 - A very close resemblance to ActiveRecord, which I am not a fan of

Those are negative things. There are quite a few positives in there - it's some of the best code I've ever seen and [reading the source](https://github.com/elixir-lang/ecto) is one of the main ways I learned Elixir. These are the early days - this repo is hear to demonstrate some ideas and, possibly, to build on.

No, **Moebius won't run on MySQL**. It's a dedicated PostgreSQL solution.

## Inspiration

If you've [ever used Sequel](http://sequel.jeremyevans.net/rdoc/) for Ruby, this will look familiar to you. At it's core, Moebius embraces the idea of pushing/transforming data through a functional pipeline. You select/shape/reduce as you need.

This is still very much a work in progress.


## Installation

Installing Moebius is pretty straightforward:

  1. Add moebius to your list of dependencies in `mix.exs`:

        def deps do
          [{:moebius, "~> 0.0.1"}]
        end

  2. Ensure moebius is started before your application:

        def application do
          [applications: [:moebius]]
        end


Next, in your config, specify how to connect. We just pass along the connection bits to Postgrex (the PG driver) so you can add whatever you want based on their options:

```
config :moebius, connection: [database: "MY_DB", extensions: [{Postgrex.Extensions.JSON, library: Poison}]], scripts: "test/db"
```

## Simple Examples

Here are some very, very basic examples. I'm sure the API will be changing in a big way - so if you want to see what's happening (until I bake this a bit) please have a look at the test.

Everything starts with the db:

```ex
cmd = db(:users)
```

That produces the `QueryCommand` that we will then shape as we need:

```ex
cmd = db(:users)
    |> filter(id: 1)
```

We still have a command here, one that we can pass along and do all kinds of things with:

```ex
cmd = db(:users)
    |> filter(id: 1, name: "Steve")
    |> sort(:name, :desc)
    |> limit(10)
    |> offset(2)
    |> select
```

If I did the API right, this should be pretty obvious. And no, order is not important. The final bit there builds a `:select` command from what has come before. We can execute it thus:

```ex
{:ok, res} = db(:users)
    |> filter(id: 1, name: "Steve")
    |> sort(:name, :desc)
    |> limit(10)
    |> offset(2)
    |> select
    |> run
```

If you don't want to deal with my abstractions, just use SQL:

```ex
{:ok, res} = run "select * from users where id=1 limit 1 offset 1;"
```

## Full Text indexing

Because I love it:

```ex
{:ok, res} = db(:users)
      |> search("Mike", [:first, :last, :email])
      |> run
```

The `search` function builds a `tsvector` search on the fly for you and executes it over the columns you send in. The results are ordered in descending order using `ts_rank`

## SQL Files

I built this for [MassiveJS](https://github.com/robconery/massive-js) and I liked the idea, which is this: *some people love SQL*. I'm one of those people. I'd much rather work with a SQL file than muscle through some weird abstraction.

With this library you can do that. Just create a scripts directory and specify it in the config (see above), then execute:

```ex
{:ok, res} = sql_file(:my_groovy_query, "a param")
  |> single
```

## Adding, Updating, Deleting

Inserting is pretty straightforward:

```ex
{:ok, res} = db(:users)
    |> insert(email: "test@test.com", first: "Test", last: "User")
    |> execute
```

Updating can work over multiple rows, or just one, depending on the filter you use:

```ex
{:ok, res} = db(:users)
    |> filter(id: 1)
    |> update(email: "maggot@test.com")
    |> execute
```

The filter can be a single record, or affect multiple records:

```ex
{:ok, res} = db(:users)
    |> filter("id > 100")
    |> update(email: "test@test.com")
    |> execute

{:ok, res} = db(:users)
    |> filter("email LIKE %$2", "test")
    |> update(email: "ox@test.com")
    |> execute
```

Deleting works exactly the same way as `update`:

```ex
{:ok, res} = db(:users)
    |> filter("email LIKE %$2", "test")
    |> delete
    |> execute
```

## Table Joins

Table joins can be applied for a single join or piped to create multiple joins. The table names can be either atoms or binary strings. There are a number of options to customize your joins:

``` ex

  :join        # set the type of join. LEFT, RIGHT, FULL, etc. defaults to INNER
  :on          # specify the table to join on
  :foreign_key # specify the tables foreign key column
  :primary_key # specify the joining tables primary key column
  :using       # used to specify a USING queries list of columns to join on

```

The simplest example is a basic join:

```ex
{:ok, res} = db(:customers)
    |> join(:orders)
    |> select
    |> execute
```

For multiple table joins you can specify the table that you want to join on:

```ex
{:ok, res} = db(:customers)
    |> join(:orders, on: :customers)
    |> join(:items, on: :orders)
    |> select
    |> execute
```

## Transactions

I'm still working on an approach for this, but my initial inclination is usually to write SQL that does exactly what I want. I *will* have something in place in a week or so, but if you are OK using SQL, then build yourself a CTE (have a look in the test/db directory at `cte.sql`) which is a transactional operation. You'll write less code probably :).

## Aggregates etc

I still need to build these - just a matter of time. Probably happen this week.

## Help? Please?

Even if you tell me this sucks, that's still helpful :). I'd love any that you want to give.
