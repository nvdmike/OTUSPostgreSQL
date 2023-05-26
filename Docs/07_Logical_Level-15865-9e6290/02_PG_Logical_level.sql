-- подключаемся к бд
\c logical;
--перенос таблицы из схемы в схему. Логическая операция быстрая
AlTER TABLE tbl2 SET SCHEMA public;
--перейти в расширенный режим просмотра или DBEAVER
\x
-- показать все таблицы
SELECT * FROM pg_class WHERE relkind = 'r';
-- уберем из просмотра системные
SELECT * FROM pg_class WHERE relkind = 'r' AND relname NOT LIKE 'pg%' AND relname NOT LIKE 'sql%';
--узнать oid таблицы
SELECT 'tbl1'::regclass::oid;
--где находится каталог PGDATA
SHOW data_directory;
--узнать oid базы данных
SELECT oid, datname FROM pg_database WHERE datname='logical';
--можно узнать через функцию
SELECT pg_relation_filepath('pg_class');
--как посмотреть какой запрос отправляет PG, установить настройку
\set ECHO_HIDDEN on
--проверям какой запрос уходит на зпрос списка баз данных
\l
--или списко таблиц
\dt
-- вернем обратно
\set ECHO_HIDDEN off


--внешние таблицы, view из другой таблицы
\c dvdrental
--Создадим view просмотра данных из другой базы dvdrental
select * from public.actor_info;
--сколько пользователей
\du+
-- или select * from pg_user;
--создадим учетку
CREATE ROLE student with LOGIN PASSWORD 'Pa$$w0rd';
--дадим полномочия
GRANT SELECT ON public.actor_info TO student;
-- проверим, что работает 
psql -U student -d dvdrental -h localhost
-- перейдем в базу logical
\c logical
--создадим в базе Logical расширение, которое из коробки ничего создавать не нужно https://www.postgresql.org/docs/current/postgres-fdw.html
-- super user postgres : sudo su postgres; psql
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
--создадим внешний сервер для базы logical
CREATE SERVER IF NOT EXISTS ext_server
FOREIGN DATA WRAPPER postgres_fdw
options (
		host 'localhost',
		dbname 'dvdrental',
		port '5432'
		);		
--удалим если есть мапинг пользователя с текущим пользователем postgres, так как командная строка работает из под него
DROP USER MAPPING IF EXISTS FOR current_user SERVER ext_server	
--создадим мапинг student будет заходить из под postgres
CREATE USER MAPPING FOR current_user
SERVER 	ext_server
OPTIONS (user 'student', password 'Pa$$w0rd');

--удалим если есть образ удаленной таблицы
DROP FOREIGN TABLE IF EXISTS public.actor_info;
--создадим образ удаленной таблицы с типами из представления, это важно
CREATE FOREIGN TABLE IF NOT EXISTS public.actor_info
(actor_id int, first_name varchar(45), last_name varchar(45), film_info text)
SERVER ext_server
OPTIONS (schema_name 'public', table_name 'actor_info');
--проверим, что работает
select * from public.actor_info;

