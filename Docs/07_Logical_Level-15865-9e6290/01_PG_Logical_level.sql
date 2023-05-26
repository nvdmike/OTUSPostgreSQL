--ssh mike@192.168.0.34
--подключение к pg
sudo -i -u postgres psql
CREATE DATABASE Logical;
--расположение hba файла
show hba_file;
--расположение конфиг файла
show config_file;
--соджержание баз данных в кластере
\l
--больше информации
\l+
--получение данных о таблицах
\dt
-- Access Method = Heap в выводе команды \dt означает, что таблица не имеет индексов и использует стандартный метод доступа к данным - "куча" (heap)
\dt+
-- можно использовать запрос где
-- datistemplate указывает на факт того, что база данных может выступать в качестве шаблона в команде CREATE DATABASE
-- datallowconn указывает на возможность подключаться к этой базе данных (однако текущие сессии не закрываются при сбросе этого флага)
-- datconnlimit - ограничения по подключениям к базе. где -1 нет ограничений
SELECT oid, datname, datistemplate, datallowconn, datconnlimit FROM pg_database;
--к какой базе данных подключены
SELECT current_database();
--узнать размер базы данных из двух функций с приведением Кб
SELECT pg_size_pretty(pg_database_size('dvdrental'));
--переподключение к базе
\c dvdrental;

-- schema
--какие схемы есть в данной бд
\dn
-- или через запрос
SELECT * FROM pg_namespace;
-- какая схема текущая nspowner=oid=pg_authid.oid=Owner of the namespace  
--nspacl=Access privileges; see GRANT and REVOKE for details
SELECT current_schema();
--узнать какая реальная схема используется в поиске + системные schema так как user нет такой схемы
SELECT current_schemas(true);
--как получить описание любой таблицы например таблицы actor из dvdrental
\d actor;
-- можно проверить 
select * from actor limit 1 \gx
-- создадим две таблички
\c logical;
create table tbl1(i int);
create schema postgres;
create table tbl2(i int);
-- проверим по схеме public
\dt public.*
-- где же таблица tbl2? \dt

-- search_path
-- Эта переменная определяет порядок, в котором будут просматриваться схемы при поиске объекта (таблицы, типа данных, функции и т. д.), 
--к которому обращаются просто по имени, без указания схемы.
SHOW search_path;
-- проверим изменение поиска по схемам добавилась новая схема postgres и 
-- новые объекты будут попадать в первую схему, если не указана схема явно
SELECT current_schemas(true);
-- изменим search_path что бы сначала использовалась схема public, а не user пользовательскавя. 
-- Будет работать в рамках сессии
-- Можно установить в рамках одной бд ALTER DATABASE logical SET search_path="user",public
-- поменяется поведение \dt только в первой схеме
-- SET search_path TO public, "user";
--создадим временную таблицу, она создаться в своей схеме pg_temp_4 
-- можно проверить через  SELECT * FROM pg_namespace;
create temp table tbl1(i int);
-- по каждой схеме можно посмотреть список таблиц
\dt public.*
\dt postgres.*
\dt pg_temp_4.* -- или pg_temp_3.*
-- можно поменять схему ALTER TABLE [tablename] SET SCHEMA [new_schema]
-- или через запрос 
select * from pg_tables \gx
-- изменим порядок в search_path
SET search_path TO public, "user", pg_catalog, pg_temp;
-- проверим 
\dt
SHOW search_path;
--поменяем обратно
SET search_path TO "$user", public; 
--проверим 
\dt
SHOW search_path; 





