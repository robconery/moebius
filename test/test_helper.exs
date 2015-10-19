ExUnit.start()

sql = "
drop table logs;
drop table if exists users;
drop table if exists products;

create table users(
  id serial primary key,
  email varchar(50) unique not null,
  first varchar(50),
  last varchar(50),
  profile jsonb
);

create table products(
  sku varchar(50) not null primary key,
  name varchar(255) not null,
  price decimal(10,2) not null default 0,
  description text,
  search tsvector,
  variants jsonb
);

create table logs(
  id serial primary key not null,
  user_id references users(id),
  log text
);
"

Moebius.Runner.run_with_psql sql, "meebuss"
