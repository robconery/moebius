ExUnit.start()

sql = "
drop index if exists idx_docs;
drop table if exists user_docs;
drop table if exists logs;
drop table if exists users;
drop table if exists products;

create table users(
  id serial primary key,
  email varchar(50) unique not null,
  first varchar(50),
  last varchar(50),
  order_count integer not null default 10,
  profile jsonb
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
  body jsonb not null
);

create index idx_docs on user_docs using GIN(body jsonb_path_ops);

insert into users(email, first, last) values('rob@test.com','Rob','Blah');
insert into users(email, first, last) values('jill@test.com','Jill','Gloop');
insert into users(email, first, last) values('mary@test.com','Mary','Muggtler');
insert into users(email, first, last) values('mike@test.com','Mike','Ghruoisl');
"

case Moebius.Runner.run_with_psql sql do
  {_res, 0} -> true
  {:error, err} -> raise err
end
