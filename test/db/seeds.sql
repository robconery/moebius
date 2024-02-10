insert into users(email, first, last) values('rob@test.com','Rob','Blah');
insert into users(email, first, last) values('jill@test.com','Jill','Gloop');
insert into users(email, first, last) values('mary@test.com','Mary','Muggtler');
insert into users(email, first, last) values('mike@test.com','Mike','Ghruoisl');

insert into date_night(date) values(now());
insert into date_night(date) values(now() - '1 day' :: interval);
insert into date_night(date) values(now() + '2 days' :: interval);
insert into date_night(date) values(now() + '1 year' :: interval);