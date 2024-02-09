-- drop index if exists idx_docs;
drop table if exists user_docs;
drop table if exists logs;
drop table if exists users;
drop table if exists products;
drop table if exists date_night;
drop table if exists sessions;

create table users(
  id serial primary key,
  email varchar(50) unique not null,
  first varchar(50),
  last varchar(50),
  order_count integer not null default 10,
  profile jsonb,
  roles varchar[]
);

create table products(
  id serial primary key not null,
  sku varchar(50) not null,
  name varchar(255) not null,
  price decimal(10,2) not null default 0,
  description text,
  search tsvector,
  variants jsonb
);

create table logs(
  id serial primary key not null,
  user_id integer references users(id),
  log text
);

create table user_docs(
  id serial primary key not null,
  body jsonb not null,
  created_at timestamptz default now(),
  updated_at timestamptz
);

create index idx_docs on user_docs using GIN(body jsonb_path_ops);

create table date_night(id serial primary key, date timestamptz);

create table sessions(
  id varchar(36) primary key not null,
  body jsonb not null,
  search tsvector,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

create index idx_sessions on sessions using GIN(body jsonb_path_ops);