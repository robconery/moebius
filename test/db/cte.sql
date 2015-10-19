with new_user as(
  insert into users(email)
  values($1) returning *
), logged as (
  insert into logs(user_id, log)
  select id, 'New User added' from new_user
)
select id, email from new_user;
