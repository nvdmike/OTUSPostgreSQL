
-- проверим размер кеша
SELECT setting, unit FROM pg_settings WHERE name = 'shared_buffers'; 
-- уменьшим количество буферов для наблюдения
ALTER SYSTEM SET shared_buffers = 200;


-- рестартуем кластер после изменений
sudo pg_ctlcluster 13 main restart

SHOW shared_buffers;


CREATE DATABASE buffer_temp;
\c buffer_temp
CREATE TABLE test(i int);
-- сгенерируем значения
INSERT INTO test SELECT s.id FROM generate_series(1,100) AS s(id); 
SELECT * FROM test limit 10;

-- создадим расширение для просмотра кеша
CREATE EXTENSION pg_buffercache; 

\dx+

CREATE VIEW pg_buffercache_v AS
SELECT bufferid,
       (SELECT c.relname FROM pg_class c WHERE  pg_relation_filenode(c.oid) = b.relfilenode ) relname,
       CASE relforknumber
         WHEN 0 THEN 'main'
         WHEN 1 THEN 'fsm'
         WHEN 2 THEN 'vm'
       END relfork,
       relblocknumber,
       isdirty,
       usagecount
FROM   pg_buffercache b
WHERE  b.relDATABASE IN (    0, (SELECT oid FROM pg_DATABASE WHERE datname = current_database()) )
AND    b.usagecount is not null;

SELECT * FROM pg_buffercache_v WHERE relname='test';

SELECT * FROM test limit 10;

UPDATE test set i = 2 WHERE i = 1;

-- увидим грязную страницу
SELECT * FROM pg_buffercache_v WHERE relname='test';


-- даст пищу для размышлений над использованием кеша -- usagecount > 3
SELECT c.relname,
  count(*) blocks,
  round( 100.0 * 8192 * count(*) / pg_table_size(c.oid) ) "% of rel",
  round( 100.0 * 8192 * count(*) FILTER (WHERE b.usagecount > 3) / pg_TABLE_size(c.oid) ) "% hot"
FROM pg_buffercache b
  JOIN pg_class c ON pg_relation_filenode(c.oid) = b.relfilenode
WHERE  b.relDATABASE IN (
         0, (SELECT oid FROM pg_DATABASE WHERE datname = current_database())
       )
AND    b.usagecount is not null
GROUP BY c.relname, c.oid
ORDER BY 2 DESC
LIMIT 10;

-- сгенерируем значения с текстовыми полями - чтобы занять больше страниц
CREATE TABLE test_text(t text);
INSERT INTO test_text SELECT 'строка '||s.id FROM generate_series(1,500) AS s(id); 
SELECT * FROM test_text limit 10;
SELECT * FROM test_text;
SELECT * FROM pg_buffercache_v WHERE relname='test_text';

-- интересный эффект
vacuum test_text;


-- посмотрим на прогрев кеша
-- рестартуем кластер для очистки буферного кеша
sudo pg_ctlcluster 13 main restart

\c buffer_temp
SELECT * FROM pg_buffercache_v WHERE relname='test_text';
CREATE EXTENSION pg_prewarm;
SELECT pg_prewarm('test_text');
SELECT * FROM pg_buffercache_v WHERE relname='test_text';

-- pg_current_wal_flush_lsn		-- позицию сброса данных журнала

-------------WAL-----------------
\c buffer_temp
SELECT * FROM pg_ls_waldir() LIMIT 10;
CREATE EXTENSION pageinspect;
BEGIN;
-- текущая позиция lsn
SELECT pg_current_wal_insert_lsn();		-- Выдаёт текущую позицию добавления в журнале предзаписи
-- посмотрим какой у нас wal file
SELECT pg_walfile_name('0/___');
SELECT pg_walfile_name('0/1670928');	-- Выдаёт для заданной позиции в журнале предзаписи имя соответствующего файла WAL

-- после UPDATE номер lsn изменился
SELECT lsn FROM page_header(get_raw_page('test_text',0));
commit;

UPDATE test_text set t = '1' WHERE t = 'строка 1';
SELECT pg_current_wal_insert_lsn();
SELECT lsn FROM page_header(get_raw_page('test_text',0));
SELECT '0/1672DB8'::pg_lsn - '0/1670928'::pg_lsn;
sudo /usr/lib/postgresql/13/bin/pg_waldump -p /var/lib/postgresql/13/main/pg_wal -s 0/1670928 -e 0/1672DB8 000000010000000000000001



---Checkpoint----
-- посмотрим информацию о кластере
sudo /usr/lib/postgresql/13/bin/pg_controldata /var/lib/postgresql/13/main/
SELECT pg_current_wal_insert_lsn();
CHECKPOINT;
SELECT pg_current_wal_insert_lsn();
sudo /usr/lib/postgresql/13/bin/pg_waldump -p /var/lib/postgresql/13/main/pg_wal -s 0/173B0D0 -e 0/173D2B0 000000010000000000000001
sudo /usr/lib/postgresql/13/bin/pg_waldump -p /var/lib/postgresql/13/main/pg_wal -s 2/E0048070 -e 2/E00481B8 0000000100000002000000E0

-- Сымитируем сбой:
\c buffer_temp
INSERT INTO test_text values('сбой');

-- sudo pg_ctlcluster 13 main stop -m immediate
sudo pkill -9 postgres


sudo /usr/lib/postgresql/13/bin/pg_controldata /var/lib/postgresql/13/main/
-- кластер выключен, но статус in production
-- запускаем кластер и убеждаемся, что данные накатились
sudo pg_ctlcluster 13 main start
sudo -u postgres psql
\c buffer_temp
select * from test_text order by t asc limit 10;

sudo cat /var/log/postgresql/postgresql-13-main.log

-- Статистика bgwriter
SELECT * FROM pg_stat_bgwriter \gx

--настройка---
show fsync;
show wal_sync_method;
show data_checksums;


\c buffer_temp
SELECT pg_relation_filepath('test_text');
-- Остановим сервер и поменяем несколько байтов в странице (сотрем из заголовка LSN последней журнальной записи)
dd if=/dev/zero of=/var/lib/postgresql/13/main/base/16384/16410 oflag=dsync conv=notrunc bs=1 count=8
-- запустим сервер и попробуем сделать выборку из таблицы



-- Попробуем нагрузочное тестирование в синхронном и асинхронном режиме
pgbench -i buffer_temp
pgbench -P 1 -T 10 buffer_temp

ALTER SYSTEM SET synchronous_commit = off;

pgbench -P 1 -T 10 buffer_temp
-- почему не увидели разницы???





SELECT pg_reload_conf(); -- конфигурацию-то не перечитали %)
sudo pg_ctlcluster 13 main reload
-- на простых старых hdd разница до 30 раз 


