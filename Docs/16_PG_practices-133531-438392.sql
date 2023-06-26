show lc_collate;
show cpu_tuple_cost;

select * from pg_settings where name='cpu_tuple_cost';

--Свойства метода доступа
select a.amname, p.name, pg_indexam_has_property(a.oid,p.name)
from pg_am a,
unnest(array['can_order','can_unique','can_multi_col','can_exclude']) p(name)
where a.amname = 'btree' order by a.amname;

---список всех существующих классов операторов

SELECT am.amname AS index_method,
       opc.opcname AS opclass_name,
       opc.opcintype::regtype AS indexed_type,
       opc.opcdefault AS is_default
    FROM pg_am am, pg_opclass opc
    WHERE opc.opcmethod = am.oid
    and am.amname = 'btree'
    ORDER BY index_method, opclass_name;

---классы операторов----
SELECT am.amname AS index_method,
       opf.opfname AS opfamily_name,
       amop.amopopr::regoperator AS opfamily_operator
    FROM pg_am am, pg_opfamily opf, pg_amop amop
    WHERE opf.opfmethod = am.oid AND
          amop.amopfamily = opf.oid
          and am.amname = 'btree'
    ORDER BY index_method, opfamily_name, opfamily_operator;


---
drop database otus;

create database otus;

create table test as
select generate_series as id
	, generate_series::text || (random() * 10)::text as col2
    , (array['Yes', 'No', 'Maybe'])[floor(random() * 3 + 1)] as is_okay
from generate_series(1, 50000);
select * from test;


analyse test;

explain
select * from test where id = 1;

select * from pg_settings where name ='seq_page_cost';
select * from pg_settings where name ='cpu_tuple_cost';

-----вычсиление cost-----

analyse test;


explain (buffers,analyse)
select *
from test;

--(число_чтений_диска * seq_page_cost) + (число_просканированных_строк * cpu_tuple_cost)
show seq_page_cost;
show cpu_tuple_cost;
--(383*1)+(50000*0,01)

set seq_page_cost=2;
reset all;

----Смотрим планы выполнения в визуализаторах
explain
select id from test where id = 1;

CREATE INDEX CONCURRENTLY "explain_depesz_com_hint_ORLQ_1" ON test ( id );

EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON)
select id from test where id = 1;

EXPLAIN (ANALYZE, BUFFERS)
select id from test where id = 1;

drop table test;


--Уникальный индекс
drop table test;

create table test as
select generate_series as id
	, generate_series::text || (random() * 10)::text as col2
    , (array['Yes', 'No', 'Maybe'])[floor(random() * 3 + 1)] as is_okay
from generate_series(1, 50000);
alter table test add constraint uk_test_id unique(id);

---width
explain
select * from test where id = 1;

explain
select id from test where id = 1;

insert into test values (null, 12, 'Yes');
insert into test values (null, 12, 'No');
explain
select * from test where id is null;

alter table test drop constraint uk_test_id;

create unique index idx_test_id on test(id) NULLS  DISTINCT ;

explain
select * from test where id is null;

explain select *
from test
order by id desc;

drop table test;



--Составной индекс
drop table test;
create table test as
select generate_series as id
	, generate_series::text || (random() * 10)::text as col2
    , (array['Yes', 'No', 'Maybe'])[floor(random() * 3 + 1)] as is_okay
from generate_series(1, 50000);

drop index idx_test_id_is_okay;

create index idx_test_id_is_okay on test(id,is_okay);

explain
select * from test where id = 1 and is_okay = 'True';

explain
select * from test where id = 1;

analyse test;

set enable_seqscan='off';

explain analyse
select * from test where is_okay = 'Yes'; 968

create index idx_test_is_okay on test(is_okay);

explain analyse
select * from test where is_okay = 'Yes';

explain
select * from test order by id, is_okay;

explain
select * from test order by id desc , is_okay desc;

set enable_seqscan='on';
SET enable_incremental_sort = on;


explain
select * from test order by id,is_okay desc;
drop table test;


--индекс на функцию  ()
drop table test;

create table test as
select generate_series as id
	, generate_series::text || (random() * 10)::text as col2
    , (array['Yes', 'No', 'Maybe'])[floor(random() * 3 + 1)] as is_okay
from generate_series(1, 50000);


create index idx_test_id_is_okay on test(lower(is_okay));

select * from test;

explain
select * from test where is_okay = 'Yes';

explain
select is_okay from test where lower(is_okay) = 'Yes';

--частичный индекс
drop table test;
create table test as
select generate_series as id
	, generate_series::text || (random() * 10)::text as col2
    , (array['Yes', 'No', 'Maybe'])[floor(random() * 3 + 1)] as is_okay
from generate_series(1, 50000);
create index idx_test_id_100 on test(id) where id < 100;

explain
select * from test where id > 100;


--обслуживание индексов
SELECT
    TABLE_NAME,
    pg_size_pretty(table_size) AS table_size,
    pg_size_pretty(indexes_size) AS indexes_size,
    pg_size_pretty(total_size) AS total_size
FROM (
    SELECT
        TABLE_NAME,
        pg_table_size(TABLE_NAME) AS table_size,
        pg_indexes_size(TABLE_NAME) AS indexes_size,
        pg_total_relation_size(TABLE_NAME) AS total_size
    FROM (
        SELECT ('"' || table_schema || '"."' || TABLE_NAME || '"') AS TABLE_NAME
        FROM information_schema.tables
    ) AS all_tables
    ORDER BY total_size DESC

    ) AS pretty_sizes;

select * from pg_stat_user_indexes;



--неиспользуемые индексы
SELECT s.schemaname,
       s.relname AS tablename,
       s.indexrelname AS indexname,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS index_size,
       s.idx_scan
FROM pg_catalog.pg_stat_all_indexes s
   JOIN pg_catalog.pg_index i ON s.indexrelid = i.indexrelid
WHERE s.idx_scan < 100      -- has never been scanned
  AND 0 <>ALL (i.indkey)  -- no index column is an expression
  AND NOT i.indisunique   -- is not a UNIQUE index
  AND NOT EXISTS          -- does not enforce a constraint
         (SELECT 1 FROM pg_catalog.pg_constraint c
          WHERE c.conindid = s.indexrelid)
ORDER BY pg_relation_size(s.indexrelid) DESC;

SELECT
    tablename,
    indexname,
    indexdef
FROM
    pg_indexes
ORDER BY
    tablename,
    indexname;

--Индекс на timestamp (between)

drop table if exists orders;
create table orders (
    id int,
    user_id int,
    order_date date,
    status text,
    some_text text
);


insert into orders(id, user_id, order_date, status, some_text)
select generate_series, (random() * 70), date'2019-01-01' + (random() * 300)::int as order_date
        , (array['returned', 'completed', 'placed', 'shipped'])[(random() * 4)::int]
        , concat_ws(' ', (array['go', 'space', 'sun', 'London'])[(random() * 5)::int]
            , (array['the', 'capital', 'of', 'Great', 'Britain'])[(random() * 6)::int]
            , (array['some', 'another', 'example', 'with', 'words'])[(random() * 6)::int]
            )
from generate_series(1,1000000);


select *
from orders;

--cost > jit_above_cost включается JIT
explain
select *
from orders
where id < 1000000;

show jit_above_cost;

drop index idx_orders_id;
create index idx_orders_id on orders(some_text);

explain
select *
from orders
where id <1500000;

explain
select *
from orders
order by id;

explain
select *
from orders
order by id desc;

--Индекс на даты
drop index if exists idx_ord_order_Date;
create index idx_ord_order_Date on orders(order_date);
explain
select *
from orders
where order_date between date'2020-01-01' and date'2020-02-01';

--Индекс include
drop index if exists idx_ord_order_date_inc_status;
create index idx_ord_order_date_inc_status_some_include on orders(order_date,some_text);

create index idx_ord_order_date_inc_status on orders;

explain
select order_date, status,some_text
from orders
where order_date between date'2020-01-01' and date'2020-02-01';

explain
select order_date, status
from orders
where order_date between date'2020-01-01' and date'2020-02-01'
        and status = 'placed';

--Работа с лексемами
explain (analyse,buffers)
select * from orders where some_text ilike 'a%';

select some_text, to_tsvector(some_text)
from orders;

explain
select some_text, to_tsvector(some_text) @@ to_tsquery('britains')
from orders;

select some_text, to_tsvector(some_text) @@ to_tsquery('london & capital')
from orders;

select some_text, to_tsvector(some_text) @@ to_tsquery('london | capital')
from orders;

alter table orders drop column if exists some_text_lexeme;

alter table orders add column some_text_lexeme tsvector;

update orders
set some_text_lexeme = to_tsvector(some_text);

explain
select *
from orders
where some_text_lexeme @@ to_tsquery('britains');

drop index if exists search_index_ord;
CREATE INDEX search_index_ord_btree using gin ON orders (some_text_lexeme) ;

CREATE INDEX search_index_ord ON orders
    USING GIN (some_text_lexeme);

explain
select *
from orders
where some_text_lexeme @@ to_tsquery('britains');


--Расширения pgstattuple
CREATE EXTENSION pgstattuple;

drop table if exists orders;
create table orders (
    id int,
    user_id int,
    order_date date,
    status text,
    some_text text
);


insert into orders(id, user_id, order_date, status, some_text)
select generate_series, (random() * 70), date'2019-01-01' + (random() * 300)::int as order_date
        , (array['returned', 'completed', 'placed', 'shipped'])[(random() * 4)::int]
        , concat_ws(' ', (array['go', 'space', 'sun', 'London'])[(random() * 5)::int]
            , (array['the', 'capital', 'of', 'Great', 'Britain'])[(random() * 6)::int]
            , (array['some', 'another', 'example', 'with', 'words'])[(random() * 6)::int]
            )
from generate_series(1, 1000000);


create index orders_order_date on orders(order_date);

analyse orders;

select * from pg_stat_user_tables where relname='orders' ;

select * from pgstattuple('orders');

select * from pgstatindex('orders_order_date');

update orders set order_date='2021-11-01' where id < 500000;

select * from pgstattuple('orders');

select * from pgstatindex('orders_order_date');

vacuum orders;

vacuum full orders;


--Кластеризация
drop table if exists orders;

create table orders (
    id int,
    user_id int,
    order_date date,
    status text,
    some_text text
);
insert into orders(id, user_id, order_date, status, some_text)
select generate_series, (random() * 70), date'2019-01-01' + (random() * 300)::int as order_date
        , (array['returned', 'completed', 'placed', 'shipped'])[(random() * 4)::int]
        , concat_ws(' ', (array['go', 'space', 'sun', 'London'])[(random() * 5)::int]
            , (array['the', 'capital', 'of', 'Great', 'Britain'])[(random() * 6)::int]
            , (array['some', 'another', 'example', 'with', 'words'])[(random() * 6)::int]
            )
from generate_series(1, 1000000);

select * from orders;

SET work_mem = '64MB';

explain
select * from orders where order_date = '2019-04-26';

drop index if exists order_date_idx;

create index order_date_idx on orders(order_date);

cluster orders using order_date_idx;

analyse orders;

select * from orders where order_date = '2019-04-26';