drop database otus;
create database otus;

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
create index order_date_idx on orders(order_date);
cluster orders using order_date_idx;
analyse orders;


--Nested loop и товарищи
select * from pg_class;
select * from pg_attribute;

explain analyse
select *
    from pg_class c
        join pg_attribute a on c.oid = a.attrelid   where c.relname in ( 'pg_class', 'pg_namespace' );


--Смотрим как меняется использование памяти
explain analyse
select a.attrelid
    from pg_class c
        join pg_attribute a on c.oid = a.attrelid;

explain analyse
select *
    from pg_class c
        join pg_attribute a on c.oid = a.attrelid ;


--Использование темповых файлов
SET work_mem = '64kB';
SET enable_hashjoin = on;
SET enable_mergejoin = off;
SET enable_nestloop = off;
SET log_temp_files = 0;
explain (analyse,buffers)
select *
    from pg_class c
        join pg_attribute a on c.oid = a.attrelid ;
reset work_mem;
reset log_temp_files;
SET enable_hashjoin = on;
SET enable_mergejoin = on;
SET enable_nestloop = on;


--Непосредствеено соединения

create table bus (id serial,route text,id_model int,id_driver int);
create table model_bus (id serial,name text);
create table driver (id serial,first_name text,second_name text);
insert into bus values (1,'Москва-Болшево',1,1),(2,'Москва-Пушкино',1,2),(3,'Москва-Ярославль',2,3),(4,'Москва-Кострома',2,4),(5,'Москва-Волгорад',3,5),(6,'Москва-Иваново',null,null);
insert into model_bus values(1,'ПАЗ'),(2,'ЛИАЗ'),(3,'MAN'),(4,'МАЗ'),(5,'НЕФАЗ');
insert into driver values(1,'Иван','Иванов'),(2,'Петр','Петров'),(3,'Савелий','Сидоров'),(4,'Антон','Шторкин'),(5,'Олег','Зажигаев'),(6,'Аркадий','Паровозов');

select * from bus;

select * from model_bus;
select * from driver;

-- Прямое соединениие
explain
select *
from bus b
join model_bus mb
    on b.id_model=mb.id;

explain
select *
from bus b,model_bus mb
where b.id_model=mb.id;

--left join
explain
select *
from bus b
left join model_bus mb
    on b.id_model=mb.id;

--right join
explain
select *
from bus b
right join model_bus mb
    on b.id_model=mb.id;

--left with null
explain
select *
from bus b
left join model_bus mb on b.id_model=mb.id
where mb.id is null;

--right with null
select *
from bus b
right join model_bus mb on b.id_model=mb.id
where b.id
    is null;


--full join
select *
from bus b
full join model_bus mb on b.id_model=mb.id;

select *
from bus b
full join model_bus mb on b.id_model=mb.id
where b.id is null or mb.id is null;


--cross join
explain
select *
from bus b
cross join model_bus mb;

explain --(join)
select *
from bus b
cross join model_bus mb
where  b.id_model=mb.id;

select *
from bus b,model_bus mb;
--where 1=1;


--lateral join

drop table t_product;
CREATE TABLE t_product AS
    SELECT   id AS product_id,
             id * 10 * random() AS price,
             'product ' || id AS product
    FROM generate_series(1, 1000) AS id;

drop table t_wishlist;
CREATE TABLE t_wishlist
(
    wishlist_id        int,
    username           text,
    desired_price      numeric
);

INSERT INTO t_wishlist VALUES
    (1, 'hans', '450'),
    (2, 'joe', '60'),
    (3, 'jane', '1500');

SELECT * FROM t_product LIMIT 10;
SELECT * FROM t_wishlist;

explain
SELECT        *
FROM      t_wishlist AS w
    left join LATERAL  (SELECT      *
        FROM       t_product AS p
        WHERE       p.price < w.desired_price
        ORDER BY p.price DESC
        LIMIT 5
       ) AS x
on true
ORDER BY wishlist_id, price DESC;

explain
SELECT        *
FROM      t_wishlist AS w,
    LATERAL  (SELECT      *
        FROM       t_product AS p
        WHERE       p.price < w.desired_price
        ORDER BY p.price DESC
        LIMIT 5
       ) AS x
ORDER BY wishlist_id, price DESC;



--Порядок join (параметры планировщика)
drop table test;
CREATE TABLE test AS
    SELECT    (random()*100)::int AS id,
             'product ' || id AS product
    FROM generate_series(1, 10000) AS id;

select * from test;

drop table test_2;
create table test_2 (id int);
insert into test_2 values (1);

select * from test_2;

SET enable_hashjoin = off;
SET enable_mergejoin = off;
SET enable_nestloop = on;


set join_collapse_limit to 8;    set join_collapse_limit to 1;

explain
select *
from test_2 t2
inner join test t1
on t2.id=t1.id
inner join test_2 t3
on t3.id=t2.id
inner join test_2 t4
on t3.id=t4.id;

--Union intersect except

DROP TABLE IF EXISTS top_rated_films;
CREATE TABLE top_rated_films(
	title VARCHAR NOT NULL,
	release_year SMALLINT
);

DROP TABLE IF EXISTS most_popular_films;
CREATE TABLE most_popular_films(
	title VARCHAR NOT NULL,
	release_year SMALLINT
);

INSERT INTO
   top_rated_films(title,release_year)
VALUES
   ('The Shawshank Redemption',1994),
   ('The Godfather',1972),
   ('12 Angry Men',1957);

INSERT INTO
   most_popular_films(title,release_year)
VALUES
   ('An American Pickle',2020),
   ('The Godfather',1972),
   ('Greyhound',2020);

SELECT * FROM top_rated_films;
select * from most_popular_films;

SELECT * FROM top_rated_films
UNION ALL
SELECT * FROM most_popular_films;

SELECT * FROM top_rated_films
UNION all
SELECT * FROM most_popular_films;

SELECT * FROM top_rated_films
INTERSECT
SELECT * FROM most_popular_films;

SELECT * FROM top_rated_films
EXCEPT
SELECT * FROM most_popular_films;


SELECT * FROM  most_popular_films
EXCEPT
SELECT * FROM top_rated_films;


