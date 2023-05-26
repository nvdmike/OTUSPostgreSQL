--проверим пользователя
SELECT current_user;
--создадим пользователя
CREATE USER tuser PASSWORD 'Pa$$w0rd';
-- подключаемся в базе U заглавная, базы видит.
psql -h localhost -d logical -U tuser;
-- проверим, что данные доступны для пользователя postgres и не доступны для tuser;
select * from tbl1;
--вы должны иметь USAGE в схеме, чтобы использовать объекты внутри нее, но наличие USAGE в 
--схеме само по себе недостаточно для использования объектов в схеме, вы также должны иметь права на сами объекты
-- из под postgres !!!
GRANT SELECT ON ALL TABLES IN SCHEMA public TO tuser;
-- использовать объекты, не имея права их изменять. если пользователь tuser хочет использовать какие-либо другие объекты в схеме public, 
-- например, функции, то ему нужно будет получить разрешение на их использование с помощью GRANT USAGE ON SCHEMA public TO tuser. 
-- GRANT  USAGE  ON SCHEMA public TO tuser;
--создадим из под posgres пользвателя таблицу
create table public.tbl3(i int);
insert into public.tbl3 values (3),(66);
-- проверим, что данные доступны для пользователя postgres и не доступны для tuser
-- После создания таблицы public.tbl3 другим пользователем posgres, эта таблица не будет доступна для выборки пользователю tuser, 
-- потому что по умолчанию в PostgreSQL таблицы создаются с правами доступа только для пользователя, который их создал. 
select * from public.tbl3;
-- 
GRANT SELECT ON public.tbl3 TO tuser; 
--проверим что появиль права у tuser на tbl3
select * from public.tbl3;
--проверка привелегний на таблице
\dp public.tbl3
-- postgres=arwdDxt/postgres+  описываемый_пользователь/пользователь_выдавший_правв+
-- student=r/postgres       +   так же пользователь postgres выдал права на чтение  роли student
-- tuser=r/postgres             так же пользователь postgres выдал права на чтение  роли  tuser
-- =r/postgres                  сообащет о том, что выданы права на чтение роли public, а public не отображается. 

-- права на схему (прикол)!
-- Команда REVOKE лишает одну или несколько ролей прав, назначенных ранее. Ключевое слово PUBLIC обозначает неявно определённую группу всех ролей.
REVOKE ALL ON SCHEMA public FROM tuser;
-- проверяи из под пользователя tuser
select * from public.tbl3;
-- сравним с конкретным отзывом
REVOKE ALL ON public.tbl3 FROM tuser;
-- выдаем права пользователю
GRANT SELECT ON ALL TABLES IN SCHEMA public TO tuser;

