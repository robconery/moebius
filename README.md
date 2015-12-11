![travis](https://travis-ci.org/robconery/moebius.svg?branch=master) [![Hex.pm Version](https://img.shields.io/hexpm/v/moebius.svg)](https://hex.pm/packages/moebius)

# Moebius: A functional query tool for Elixir and PostgreSQL.

I love working with Elixir but so far there hasn't been all that much choice when working with a database. Ecto works very well, but to me ORMs are just a bit out of place in the functional landscape of Elixir. I wanted to explore some options, so I made this package.

## Documentation

API documentation is available at http://hexdocs.pm/moebius

## Building docs from source

```bash
$ MIX_ENV=dev mix docs
```

## Inspiration

If you've [ever used Sequel](http://sequel.jeremyevans.net/rdoc/) for Ruby, this will look familiar to you. At its core, Moebius embraces the idea of pushing/transforming data through a functional pipeline. You select/shape/reduce as you need.

## Installation

Installing Moebius is pretty straightforward:

  1. Add moebius to your list of dependencies in `mix.exs`:

        def deps do
          [{:moebius, "~> 1.0.8"}]
        end

  2. Ensure moebius is started before your application:

        def application do
          [applications: [:moebius]]
        end


Next, in your config, specify how to connect. We just pass along the connection bits to Postgrex (the PG driver) so you can add whatever you want based on their options:

```
config :moebius, connection: [
  database: "MY_DB"
], scripts: "test/db"
```

## Simple Examples

The API is built around the concept of transforming raw data from your database into something you need. We lean on Elixir's pipe operator for this, and it's the core of the API.

Everything starts with the db:

```ex
cmd = db(:users)
```

That produces the `QueryCommand` that we will then shape as we need:

```ex
result = db(:users)
    |> filter(id: 1)
    |> first
```

This returns a user with the id of 1.

```ex
result = db(:users)
    |> filter(name: "Steve")
    |> sort(:city, :desc)
    |> limit(10)
    |> offset(2)
    |> to_list
```

Hopefully it's fairly straightforward what this query returns. All users named Steve sorted by city... skipping the first two, returning the next 10.

An `IN` query happens when you pass an array:

```ex
result = db(:users)
    |> filter(:name, ["mark", "biff", "skip"])
    |> to_list

#or, if you want to be more precise

result = db(:users)
    |> filter(:name, in: ["mark", "biff", "skip"])
    |> to_list
```

A NOT IN query happens when you specify the `not_in` key:

```ex
result = db(:users)
    |> filter(:name, not_in: ["mark", "biff", "skip"])
    |> to_list
```

If you don't want to deal with my abstractions, just use SQL:

```ex
result = run "select * from users where id=1 limit 1 offset 1;"
```

## Full Text indexing

Because I love it:

```ex
result = db(:users)
      |> search(for: "Mike", in: [:first, :last, :email])
      |> to_list
```

The `search` function builds a `tsvector` search on the fly for you and executes it over the columns you send in. The results are ordered in descending order using `ts_rank`.


## JSONB Support

Moebius supports using PostgreSQL as a document store in its entirety. Get your project off the ground and don't worry about migrations - just store documents, and you can normalize if you need to later on.

Start by importing `Moebius.DocumentQuery` and saving a document:

```ex
import Moebius.DocumentQuery

new_user = db(:friends)
  |> save(email: "test@test.com", name: "Moe Test")
```

Two things happened for us here. The first is that `friends` did not exist as a document table in our database, but `save/2` did that for us. This is the table that was created on the fly:

```sql
create table NAME(
  id serial primary key not null,
  body jsonb not null,
  search tsvector,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

-- index the search and jsonb fields
create index idx_NAME_search on NAME using GIN(search);
create index idx_NAME on NAME using GIN(body jsonb_path_ops);
```

The entire `DocumentQuery` module works off the premise that this is how you will store your JSONB docs. Note the `tsvector` field? That's PostgreSQL's built in full text indexing. We can use that if we want during by adding `searchable/1` to the pipe:

```ex
import Moebius.DocumentQuery

new_user = db(:friends)
  |> searchable([:name])
  |> save(email: "test@test.com", name: "Moe Test")
```

By specifying the searchable fields, the `search` field will be updated with the values of the name field.

Now, we can query our document using full text indexing which is optimized to use the GIN index created above:

```ex
user = db(:friends)
  |> search("test.com")
```

Or we can do a simple filter:

```ex
user = db(:friends)
  |> contains(email: "test@test.com")
  |> to_list
```

This query is optimized to use the `@` (or "contains" operator), using the *other* GIN index specified above. There's more we can do...

```ex
users = db(:friends)
  |> filter(:money_spent, ">", 100)
  |> to_list
```

This runs a full table scan so is not terribly optimal, but it does work if you need it once in a while. You can also use the existence (`?`) operator, which is very handy for querying arrays:

```ex
buddies = db(:friends)
  |> exists(:tags, "best")
  |> to_list
```

This will allow you to query embeded documents and arrays rather easily, but again doesn't use the JSONB-optimized GIN index. You *can* index for using existence, have a look at the PostgreSQL docs.


## SQL Files

I built this for [MassiveJS](https://github.com/robconery/massive-js) and I liked the idea, which is this: *some people love SQL*. I'm one of those people. I'd much rather work with a SQL file than muscle through some weird abstraction.

With this library you can do that. Just create a scripts directory and specify it in the config (see above), then execute your file without an extension. Pass in whatever parameters you need:

```ex
result = sql_file(:my_groovy_query, "a param")
```

## Adding, Updating, Deleting (Non-Documents)

Inserting is pretty straightforward:

```ex
result = db(:users)
    |> insert(email: "test@test.com", first: "Test", last: "User")
```

Updating can work over multiple rows, or just one, depending on the filter you use:

```ex
result = db(:users)
    |> filter(id: 1)
    |> update(email: "maggot@test.com")
```

The filter can be a single record, or affect multiple records:

```ex
result = db(:users)
    |> filter("id > 100")
    |> update(email: "test@test.com")

result = db(:users)
    |> filter("email LIKE $2", "%test")
    |> update(email: "ox@test.com")

```

Deleting works exactly the same way as `update`, but returns the count of deleted items in the result:

```ex
result = db(:users)
    |> filter("email LIKE $2", "%test")
    |> delete

#result.deleted = 10, for instance
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
result = db(:customers)
    |> join(:orders)
    |> select
    |> execute
```

For multiple table joins you can specify the table that you want to join on:

```ex
result = db(:customers)
    |> join(:orders, on: :customers)
    |> join(:items, on: :orders)
    |> select
    |> execute
```

## Transactions

Transactions are facilitated by using a callback that has a `pid` on it, which you'll need to pass along to each query you want to be part of the transaction. The last execution will be returned. If there's an error, an `{:error, message}` will be returned instead and a `ROLLBACK` fired on the transaction. No need to `COMMIT`, it happens automatically:

```ex
result = transaction fn(pid) ->
  new_user = with(:users)
    |> insert(pid, email: "frodo@test.com")

  with(:logs)
    |> insert(pid, user_id: new_user.id, log: "Hi Frodo")

  new_user
end
```
I'm using `with` here, which is an alias for `db` that just reads nicer.

## A Note on Readability

You'll find a number of aliases in the code base that are there to help with a few things:

 - Putting your mind into *functional mode*, which basically means thinking of your database as a bunch of data waiting to be transformed.
 - Readability. Code is for humans, and understanding what a query is doing (or wanting to do) is really important. So you'll see aliases like `with` and `remove` etc. It's up to you and your style.

[Have a look through the docs](http://hexdocs.pm/moebius/1.0.0/Moebius.Query.html) and you'll see what I mean.

## Aggregates

Aggregates are built with a functional approach in mind. This might seem a bit odd, but when working with any relational database, it's a good idea to think about gathering your data, grouping it, and reducing it. That's what you're doing whenever you run aggregation queries.

So, to that end, we have:

```
sum = db(:products)
  |> map("id > 1")
  |> group(:sku)
  |> reduce(:sum, :id)
```

This might be a bit verbose, but it's also very very clear to whomever is reading it after you move on. You can work with any aggregate function in PostgreSQL this way (AVG, MIN, MAX, etc).

The interface is designed with *routine* aggregation in mind - meaning that there are some pretty complex things you can do with PostgreSQL queries. If you like doing that, I fully suggest you flex our SQL File functionality and write it out there - or create yourself a cool function and call it with our Function interface.

## Functions

PostgreSQL allows you to do so much, especially with functions. If you want to encapsulate a good time, you can execute it with Moebius:

```ex
party = function(:good_time, [me, you])
```

You get the idea. If your function only returns one thing, you can specify you don't want an array back:

```ex
no_party = function(:bad_time, :single [me])
```

## Help?

I would love to have your help! I am just learning Elixir and have had a great time putting this library together. If you find some idiomatic way of doing something or have some ideas for improvement, please let me know.

Also, I do ask that if you do find a bug, please add a test to your PR that shows the bug and how it was fixed.

Thanks!
