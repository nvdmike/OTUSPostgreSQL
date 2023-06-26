----------- Подготовим терраформ для развертывании в яо
$Env:YC_TOKEN=$(yc iam create-token)
$Env:YC_CLOUD_ID=$(yc config get cloud-id)
$Env:YC_FOLDER_ID=$(yc config get folder-id)
terraform apply


------------ Ставим Postgresql
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' \
&& wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo tee /etc/apt/trusted.gpg.d/pgdg.asc &>/dev/null \
&& sudo apt update \
&& sudo apt install postgresql postgresql-client -y \
&& systemctl status postgresql


-------- Смотрим настройки статистики ------
show track_activities;
show track_counts;
show track_functions;
show track_io_timing;

--------- pg_stat_database -----
select datname
     , numbackends
     , xact_comm
         it
     , xact_rollback
     , blks_read
     , blks_hit
     , tup_returned
     , tup_fetched
     , tup_inserted
     , tup_updated
     , tup_deleted
     , stats_reset
from pg_stat_database
where datname = 'demo';

---tup_fetched и tup_returned
select count(*)
from flights;

analyse flights;

select *
from pg_stat_database
where datname = 'demo';

--сброс статистики
select pg_stat_reset();

--------pg_class-----------
select * from pg_class; --relpages, reltuples

select *
from pg_class
where relname = 'flights'; --65664

select
      pg_size_pretty(pg_table_size(relid)) as table_size
 from
      pg_catalog.pg_statio_all_tables
where
      schemaname = 'bookings'
  and relname like 'flights';



explain --rows
select *
from bookings.flights;

select relkind, count(*)
from pg_class
group by relkind;

----------------pg_stats--------------------

select * from pg_stats;


select *
from pg_stats
where tablename = 'flights';

---null_fracsds
select sum(case when actual_arrival is null then 1 else null end)::numeric / count(*)
from bookings.flights;

--ndisninct
select count(distinct flight_no)
from bookings.flights;

---most_common_values
select attname, most_common_vals,array_length(most_common_vals,1),n_distinct
from pg_stats
where tablename= 'flights';

alter table flights alter column arrival_airport set statistics 200;
alter table flights alter column flight_no set statistics 200;
analyse flights;

select attname, most_common_vals,array_length(most_common_vals,1),n_distinct
from pg_stats
where tablename= 'flights';

select *
from pg_stats
where tablename = 'flights';

--Посмотрим корелляцию
drop table if exists test1;
create table test1 as
    select *
from generate_series(1, 10000);

--Без analalyse статистика не собирается
select correlation
from pg_stats
where tablename = 'test1';

analyse test1;

select correlation
from pg_stats
where tablename = 'test1';

drop table test2;
create table test2 as
select *
from test1
order by random();
analyse test2;

select correlation
from pg_stats
where tablename = 'test2';

select * from test2;
create index generate_series_idx on test2(generate_series);
select correlation
from pg_stats
where tablename = 'test2';
analyse test2;
cluster generate_series_idx on test2;

drop table test3;
create table test3 as
select *
from test1
order by generate_series desc;
analyse test3;

select correlation
from pg_stats
where tablename = 'test3';


drop table if exists test4;  -- По json статистика не ведется
create table test4 as
    select '{"some_val" : "value"}'::jsonb as c1;
analyze test4;

select * from test4;


select *
from pg_stats
where tablename = 'test4';


drop table test5;
create table test5 as
select (array[2, 4, 5]);
analyse test5;


select *
from pg_stats
where tablename = 'test5';
select * from test5;


----------кастомная статистика-----------------------------
select count(*)
from bookings.flights
where flight_no = 'PG0007' and departure_airport = 'VKO'; --121

explain
select *
from bookings.flights
where flight_no = 'PG0007' and departure_airport = 'VKO';

create statistics flights_multi(dependencies) on flight_no,  departure_airport from bookings.flights;
select * from pg_statistic_ext;
analyze bookings.flights;

explain
select *
from bookings.flights
where flight_no = 'PG0007' and departure_airport = 'VKO';

---ndistinct----
select count(*)
from
(
    select distinct departure_airport, arrival_airport
    from bookings.flights
) s1;

explain
select distinct departure_airport, arrival_airport
from bookings.flights;

create statistics flights_multi_dist(ndistinct) on departure_airport, arrival_airport from bookings.flights;
select * from pg_statistic_ext;
analyze bookings.flights;

explain
select distinct departure_airport, arrival_airport
from bookings.flights;

explain --618
select departure_airport, arrival_airport
from bookings.flights
group by departure_airport, arrival_airport;

drop statistics flights_multi_dist;

------mcv----
select * from flights;

SELECT count(*) FROM flights
WHERE departure_airport = 'DME' AND aircraft_code = 'CN1';

explain
SELECT count(*) FROM flights
WHERE departure_airport = 'DME' AND aircraft_code = 'CN1';

CREATE STATISTICS flights_mcv(mcv)
ON departure_airport, aircraft_code FROM flights;

ANALYZE flights;

explain
SELECT count(*) FROM flights
WHERE departure_airport = 'DME' AND aircraft_code = 'CN1';

SELECT values, frequency
FROM pg_statistic_ext stx
  JOIN pg_statistic_ext_data stxd ON stx.oid = stxd.stxoid,
  pg_mcv_list_items(stxdmcv) m
WHERE stxname = 'flights_mcv';

----pg_stat_activity-------
select *
from pg_stat_activity;


----pg_stat_user_tables----
select * from pg_stat_user_tables where relname = 'flights';
select * from bookings.flights;

delete from flights where flight_id=4;
select * from pg_stat_user_tables where relname = 'flights';

explain analyse
select * from bookings.flights where flight_id=182;
select * from pg_stat_user_tables where relname = 'flights';


----pg_stat_user_indexex---
select *
from pg_stat_user_indexes
where relname = 'flights';

set enable_indexscan = 'on';
explain analyse
select flight_id from bookings.flights where flight_id < 1000;
select * from demo.pg_catalog.pg_stat_user_indexes where relname = 'flights';

--поскольку idx_tup_read подсчитывает полученные из индекса элементы,
--а idx_tup_fetch — количество «живых» строк, выбранных из таблицы

--неиспользуемые индексы
SELECT s.schemaname,
       s.relname AS tablename,
       s.indexrelname AS indexname,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS index_size,
       s.idx_scan
FROM pg_catalog.pg_stat_all_indexes s
   JOIN pg_catalog.pg_index i ON s.indexrelid = i.indexrelid
WHERE s.idx_scan =0      -- has never been scanned
  AND 0 <>ALL (i.indkey)  -- no index column is an expression
  AND NOT i.indisunique   -- is not a UNIQUE index
  AND NOT EXISTS          -- does not enforce a constraint
         (SELECT 1 FROM pg_catalog.pg_constraint c
          WHERE c.conindid = s.indexrelid)
ORDER BY pg_relation_size(s.indexrelid) DESC;



---pg_stat_statements---
drop extension pg_stat_statements;
create extension pg_stat_statements;
show shared_preload_libraries;

create extension pg_stat_statements;
select * from pg_stat_statements where query like '%bookings.bookings%';

select *
from bookings.bookings where book_ref = '00000F';


----pg-hero----
-- Для того чтобы установить pgHero ubuntu нам нужно выполнить следующие команды:
sudo wget -qO- https://dl.packager.io/srv/pghero/pghero/key | sudo apt-key add - \
&& sudo wget -O /etc/apt/sources.list.d/pghero.list https://dl.packager.io/srv/pghero/pghero/master/installer/ubuntu/$(. /etc/os-release && echo $VERSION_ID).repo \
&& sudo apt update \
&& sudo apt -y install pghero \
&& pghero config:set DATABASE_URL=postgres://postgres:postgres@localhost:5432/demo \
&& pghero config:set PORT=3001 \
&& pghero config:set RAILS_LOG_TO_STDOUT=disabled \
&& pghero scale web=1


После проделанных манипуляций, вставляем ссылку http://localhost:3001/ в браузер и наблюдаем веб-интерфейс утилиты pghero


--Для centos
sudo wget -O /etc/yum.repos.d/pghero.repo   https://dl.packager.io/srv/pghero/pghero/master/installer/el/$(. /etc/os-release && echo $VERSION_ID).repo
sudo yum -y install pghero
pghero config:set DATABASE_URL=postgres://postgres:postgres@localhost:5432/demo
pghero config:set PORT=3001
pghero config:set RAILS_LOG_TO_STDOUT=disabled
pghero scale web=1


https://github.com/ankane/pghero/blob/master/guides/Linux.md
