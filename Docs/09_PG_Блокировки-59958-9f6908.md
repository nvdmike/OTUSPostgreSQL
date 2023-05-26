#   PostgreSQL. Locks.



sudo pg_ctlcluster 14 main restart
```

##  Connect Postgres
sudo -u postgres psql
create database locks;

\c locks
\l
\du
\dt
\dt+
\d table
\q

exit
```

##  Блокировки на уровне объектов

###  Пример 1 CREATE INDEX

```sql
-- Что произойдет, если выполнить команду CREATE INDEX?
-- Находим в документации, что эта команда устанавливает блокировку в режиме Share. По матрице определяем, что команда совместима сама с собой (то есть можно одновременно создавать несколько индексов) и с читающими командами. Таким образом, команды SELECT продолжат работу, а вот команды UPDATE, DELETE, INSERT будут заблокированы.
-- И наоборот — незавершенные транзакции, изменяющие данные в таблице, будут блокировать работу команды CREATE INDEX. Поэтому и существует вариант команды — CREATE INDEX CONCURRENTLY. Он работает дольше (и может даже упасть с ошибкой), зато допускает одновременное изменение данных.

-- Session #1
sudo -u postgres psql
\c locks
CREATE TABLE accounts(
  acc_no integer PRIMARY KEY,
  amount numeric
);
INSERT INTO accounts VALUES (1,1000.00), (2,2000.00), (3,3000.00);

-- Session #2
sudo -u postgres psql
\c locks
-- Во втором сеансе начнем транзакцию. Нам понадобится номер обслуживающего процесса.
BEGIN;
SELECT pg_backend_pid();

-- Какие блокировки удерживает только что начавшаяся транзакция? Смотрим в pg_locks:
SELECT locktype, relation::REGCLASS, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid = 522;
-- Транзакция всегда удерживает исключительную (ExclusiveLock) блокировку собственного номера, а данном случае — виртуального. Других блокировок у этого процесса нет.

-- Теперь обновим строку таблицы. Как изменится ситуация?
UPDATE accounts SET amount = amount + 100 WHERE acc_no = 1;

SELECT locktype, relation::REGCLASS, virtualxid AS virtxid, transactionid AS xid, mode, granted
FROM pg_locks WHERE pid = 522;
-- Теперь появились блокировки изменяемой таблицы и индекса (созданного для первичного ключа), который используется командой UPDATE. Обе блокировки взяты в режиме RowExclusiveLock. Кроме того, добавилась исключительная блокировка настоящего номера транзакции (который появился, как только транзакция начала изменять данные).


-- Session #3
sudo -u postgres psql
\c locks
-- Теперь попробуем в еще одном сеансе создать индекс по таблице.
BEGIN;
SELECT pg_backend_pid();

CREATE INDEX ON accounts(acc_no);
-- Команда «подвисает» в ожидании освобождения ресурса. Какую именно блокировку она пытается захватить? Проверим:

-- Session #1
-- SELECT pg_backend_pid();
SELECT locktype, relation::REGCLASS, virtualxid AS virtxid, transactionid AS xid, mode, granted FROM pg_locks WHERE pid = 523;
-- Видим, что транзакция пытается получить блокировку таблицы в режиме ShareLock, но не может (granted = f).

-- Находить номер блокирующего процесса, а в общем случае — несколько номеров, удобно с помощью функции, которая появилась в версии 9.6 (до того приходилось делать выводы, вдумчиво разглядывая все содержимое pg_locks):
SELECT pg_blocking_pids(523);

-- И затем, чтобы разобраться в ситуации, можно получить информацию о сеансах, к которым относятся найденные номера:
SELECT * FROM pg_stat_activity WHERE pid = ANY(pg_blocking_pids(523)) \gx

-- Session #2
-- После завершения транзакции блокировки снимаются и индекс создается.
COMMIT;

-- Session #3
COMMIT;
```

###  Пример 2 VACUUM FULL
```sql
-- Session #1
sudo -u postgres psql
\c locks

-- Чтобы лучше представить, к чему приводит появление несовместимой блокировки, посмотрим, что произойдет, если в процессе работы системы выполнить команду VACUUM FULL.

-- Пусть вначале на нашей таблице выполняется команда SELECT. Она получает блокировку самого слабого уровня Access Share. Чтобы управлять временем освобождения блокировки, мы выполняем эту команду внутри транзакции — пока транзакция не окончится, блокировка не будет снята. В реальности таблицу могут читать (и изменять) несколько команд, и какие-то из запросов могут выполняться достаточно долго.

BEGIN;
SELECT * FROM accounts;
SELECT locktype, mode, granted, pid, pg_blocking_pids(pid) AS wait_for FROM pg_locks WHERE relation = 'accounts'::regclass;

-- Session #2
sudo -u postgres psql
\c locks
-- Затем администратор выполняет команду VACUUM FULL, которой требуется блокировка уровня Access Exclusive, несовместимая ни с чем, даже с Access Share. (Такую же блокировку требует и команда LOCK TABLE.) Транзакция встает в очередь.
BEGIN;
LOCK TABLE accounts; -- аналогично VACUUM FULL

-- Session #1
SELECT locktype, mode, granted, pid, pg_blocking_pids(pid) AS wait_for
FROM pg_locks WHERE relation = 'accounts'::regclass;

-- Session #3
sudo -u postgres psql
\c locks
-- Но приложение продолжает выдавать запросы, и вот в системе появляется еще команда SELECT. Чисто теоретически она могла бы «проскочить», пока VACUUM FULL ждет, но нет — она честно занимают место в очереди за VACUUM FULL.
BEGIN;
SELECT * FROM accounts; -- что произойдет?

-- Session #1
SELECT locktype, relation::REGCLASS, mode, granted, pid, pg_blocking_pids(pid) AS wait_for
FROM pg_locks WHERE relation = 'accounts'::regclass order by pid;

-- После того, как первая транзакция с командой SELECT завершается и освобождает блокировку, начинает выполняться команда VACUUM FULL (которую мы сымитировали командой LOCK TABLE).
COMMIT;

SELECT locktype, relation::REGCLASS, mode, granted, pid, pg_blocking_pids(pid) AS wait_for
FROM pg_locks WHERE relation = 'accounts'::regclass order by pid;

-- Session #2
-- И только после того, как VACUUM FULL завершит свою работу и снимет блокировку, все накопившиеся в очереди команды (SELECT в нашем примере) смогут захватить соответствующие блокировки (Access Share) и выполниться.
COMMIT;
-- Таким образом, неаккуратно выполненная команда может парализовать работу системы на время, значительно превышающее время выполнение самой команды.

-- Session #3
COMMIT;
```

###  Мониторинг
```sql

-- С некоторыми способами мы уже познакомились: в момент возникновения долгой блокировки мы можем выполнить запрос к представлению pg_locks, посмотреть на блокируемые и блокирующие транзакции (функция pg_blocking_pids) и расшифровывать их при помощи pg_stat_activity.

-- Другой способ состоит в том, чтобы включить параметр log_lock_waits. В этом случае в журнал сообщений сервера будет попадать информация, если транзакция ждала дольше, чем deadlock_timeout (несмотря на то, что используется параметр для взаимоблокировок, речь идет об обычных ожиданиях).

-- Session #1
sudo -u postgres psql
ALTER SYSTEM SET log_lock_waits = on;
SELECT pg_reload_conf();
SHOW deadlock_timeout;

\c locks
-- Воспроизведем блокировку
BEGIN;
UPDATE accounts SET amount = amount - 100.00 WHERE acc_no = 1;

-- Session #2
sudo -u postgres psql
\c locks
BEGIN;
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
-- Вторая команда UPDATE ожидает блокировку. Подождем секунду и завершим первую транзакцию.

-- Session #1
SELECT pg_sleep(1);
COMMIT;

-- Session #2
-- Теперь и вторая транзакция может завершиться
COMMIT;
drop table accounts;
```

```bash
# И вся важная информация попала в журнал:
# Новая вкладка терминала
tail -n 10 /var/log/postgresql/postgresql-14-main.log
```


##  Блокировки на уровне строк

###  Пример 1 Исключительные режимы

```sql
-- Session #1
sudo -u postgres psql
\c locks

-- Создадим таблицу счетов, такую же, как в прошлой статье
CREATE TABLE accounts(
  acc_no integer PRIMARY KEY,
  amount numeric
);
INSERT INTO accounts VALUES (1, 100.00), (2, 200.00), (3, 300.00);
-- select * from accounts;

-- Чтобы заглядывать в страницы, нам, конечно, потребуется расширение pageinspect
CREATE EXTENSION pageinspect;

-- Для удобства создадим представление, показывающее только интересующую нас информацию: xmax и некоторые информационные биты.
CREATE VIEW accounts_v AS
SELECT '(0,'||lp||')' AS ctid,
       t_xmax as xmax,
       CASE WHEN (t_infomask & 128) > 0   THEN 't' END AS lock_only,
       CASE WHEN (t_infomask & 4096) > 0  THEN 't' END AS is_multi,
       CASE WHEN (t_infomask2 & 8192) > 0 THEN 't' END AS keys_upd,
       CASE WHEN (t_infomask & 16) > 0 THEN 't' END AS keyshr_lock,
       CASE WHEN (t_infomask & 16+64) = 16+64 THEN 't' END AS shr_lock
FROM heap_page_items(get_raw_page('accounts',0))
ORDER BY lp;

-- Начинаем транзакцию и обновляем сумму первого счета (ключ не меняется) и номер второго счета (ключ меняется):
BEGIN;
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
UPDATE accounts SET acc_no = 20 WHERE acc_no = 2;

-- Заглядываем в представление
SELECT * FROM accounts_v LIMIT 2;

-- То же самое поле xmax задействовано и при блокировании строки командой SELECT FOR UPDATE, но в этом случае проставляется дополнительный информационный бит (xmax_lock_only), который говорит о том, что версия строки только заблокирована, но не удалена и по-прежнему актуальна.

ROLLBACK;
BEGIN;
SELECT * FROM accounts WHERE acc_no = 1 FOR NO KEY UPDATE;
SELECT * FROM accounts WHERE acc_no = 2 FOR UPDATE;

SELECT * FROM accounts_v LIMIT 2;
ROLLBACK;
```

###  Пример 2 Разделяемые режимы

```sql
-- Session #1
sudo -u postgres psql
\c locks

BEGIN;
SELECT * FROM accounts WHERE acc_no = 1 FOR KEY SHARE;
SELECT * FROM accounts WHERE acc_no = 2 FOR SHARE;

SELECT * FROM accounts_v LIMIT 2;
-- В обоих случаях установлен бит keyshr_lock, а режим SHARE можно распознать, посмотрев еще один информационный бит.

/* Не завершать сессию для Примера 3 */
```

###  Пример 3 Мультитранзакции

<!-- До сих пор мы считали, что блокировка представляется номером блокирующей транзакции в поле xmax. Но разделяемые блокировки могут удерживаться несколькими транзакциями, а в одно поле xmax нельзя записать несколько номеров. Как быть?

Для разделяемых блокировок применяются так называемые мультитранзакции (MultiXact). Это группа транзакций, которой присвоен отдельный номер. Этот номер имеет ту же размерность, что и обычный номер транзакции, но номера выделяются независимо (то есть в системе могут быть одинаковые номера транзакций и мультитранзакций). Чтобы отличить одно от другого, используется еще один информационный бит (xmax_is_multi), а детальная информация об участниках такой группы и режимах блокировки находятся в файлах в каталоге $PGDATA/pg_multixact/. Естественно, последние использованные данные хранятся в буферах в общей памяти сервера для ускорения доступа. -->

```sql
-- Session #2
sudo -u postgres psql
\c locks

-- Добавим к имеющимся блокировкам еще одну исключительную, выполненную другой транзакцией (мы можем это сделать, поскольку режимы FOR KEY SHARE и FOR NO KEY UPDATE совместимы между собой):
BEGIN;
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;

SELECT * FROM accounts_v LIMIT 2;
-- В первой строке видим, что обычный номер заменен на номер мультитранзакции — об этом говорит бит xmax_is_multi.

-- Чтобы не вникать во внутренности реализации мультитранзакций, можно воспользоваться еще одним расширением, которое позволяет увидеть всю информацию о всех типах блокировок строк в удобном виде.

-- Session #1
CREATE EXTENSION pgrowlocks;
SELECT * FROM pgrowlocks('accounts') \gx
COMMIT;

-- Session #2
ROLLBACK;
```

###  Пример 4 Обновление одной и той же строки

<!-- Посмотрим, какая картина блокировок складывается, когда несколько транзакций собираются обновить одну и ту же строку. -->

```sql
-- Session #1
sudo -u postgres psql
\c locks

-- Начнем с того, что построим представление над pg_locks. Во-первых, сделаем вывод чуть более компактным, во-вторых, ограничимся только интересными блокировками (фактически, отбрасываем блокировки виртуальных номеров транзакций, индекса на таблице accounts, pg_locks и самого представления — в общем, всего того, что не имеет отношения к делу и только отвлекает).

CREATE VIEW locks_v AS
SELECT pid,
       locktype,
       CASE locktype
         WHEN 'relation' THEN relation::regclass::text
         WHEN 'transactionid' THEN transactionid::text
         WHEN 'tuple' THEN relation::regclass::text||':'||tuple::text
       END AS lockid,
       mode,
       granted
FROM pg_locks
WHERE locktype in ('relation','transactionid','tuple')
AND (locktype != 'relation' OR relation = 'accounts'::regclass);

-- Теперь начнем первую транзакцию и обновим строку.
BEGIN;
SELECT txid_current(), pg_backend_pid();

UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
SELECT * FROM locks_v WHERE pid = 638;
-- Транзакция удерживает блокировку таблицы и собственного номера. Пока все ожидаемо.


-- Session #2
sudo -u postgres psql
\c locks
-- Начинаем вторую транзакцию и пытаемся обновить ту же строку.
BEGIN;
SELECT txid_current(), pg_backend_pid();
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;

-- Session #1
SELECT * FROM locks_v WHERE pid = 522;
-- А вот тут интереснее. Помимо блокировки таблицы и собственного номера, мы видим еще две блокировки. Вторая транзакция обнаружила, что строка заблокирована первой и «повисла» на ожидании ее номера (granted = f). Но откуда и зачем взялась блокировка версии строки (locktype = tuple)?


-- Session #3
sudo -u postgres psql
\c locks
-- Что произойдет, если появится третья аналогичная транзакция? Она попытается захватить блокировку версии строки и повиснет уже на этом шаге. Проверим.
BEGIN;
SELECT txid_current(), pg_backend_pid();
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;

-- Session #1
SELECT * FROM locks_v WHERE pid = 523;

-- Session #4

sudo -u postgres psql
\c locks
BEGIN;
SELECT txid_current(), pg_backend_pid();
UPDATE accounts SET amount = amount - 100.00 WHERE acc_no = 1;

-- Session #1
SELECT * FROM locks_v WHERE pid = 525;

-- Общую картину текущих ожиданий можно увидеть в представлении pg_stat_activity, добавив информацию о блокирующих процессах:
SELECT pid, wait_event_type, wait_event, pg_blocking_pids(pid)
FROM pg_stat_activity
WHERE backend_type = 'client backend' ORDER BY pid;
-- Получается своеобразная «очередь», в которой есть первый (тот, кто удерживает блокировку версии строки) и все остальные, выстроившиеся за первым.


COMMIT;

SELECT * FROM locks_v WHERE pid = 522;
SELECT * FROM locks_v WHERE pid = 523;
SELECT * FROM locks_v WHERE pid = 525;

-- Session #2
COMMIT;
-- Session #3
COMMIT;
-- Session #4
COMMIT;
```

###  Пример 5 Разделяемые блокировки одной и той же строки

```sql
-- Session #1
sudo -u postgres psql
\c locks

-- Пусть первая транзакция заблокирует строку в разделяемом режиме.
BEGIN;
SELECT txid_current(), pg_backend_pid(); -- 638
SELECT * FROM accounts WHERE acc_no = 1 FOR SHARE;

-- Session #2
-- Вторая транзакция пытается обновить ту же строку, но не может — режимы SHARE и NO KEY UPDATE несовместимы.
BEGIN;
SELECT txid_current(), pg_backend_pid(); --522
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
-- Вторая транзакция ждет завершения первой и удерживает блокировку версии строки — пока все, как в прошлый раз.

-- Session #1
SELECT * FROM locks_v WHERE pid = 522; -- Session #2 Pid

-- Session #3
-- И тут появляется третья транзакция, которая хочет разделяемую блокировку. Беда в том, что она не пытается захватывать блокировку версии строки (поскольку не собирается изменять строку), а просто пролезает без очереди — ведь она совместима с первой транзакцией. 
BEGIN;
SELECT txid_current(), pg_backend_pid(); --523
SELECT * FROM accounts WHERE acc_no = 1 FOR SHARE;

-- Session #1
-- И вот уже две транзакции блокируют строку
SELECT * FROM pgrowlocks('accounts') \gx

-- Что теперь произойдет, когда первая транзакция завершится? Вторая транзакция будет разбужена, но увидит, что блокировка строки никуда не исчезла, и снова встанет в «очередь» — на этот раз за третьей транзакцией
COMMIT;

SELECT * FROM locks_v WHERE pid = 522; -- Session #2 Pid

-- Session #3
-- И только когда третья транзакция завершится (и если за это время не появятся другие разделяемые блокировки), вторая сможет выполнить обновление.
COMMIT;

-- Session #2
ROLLBACK;

-- Практические выводы:
-- Одновременно обновлять одну и ту же строку таблицы во многих параллельных процессах — не самая удачная идея.
-- Если и использовать разделяемые блокировки типа SHARE в приложении, то осмотрительно.
-- Проверка внешних ключей не должна мешать, поскольку ключевые поля обычно не меняются, а режимы KEY SHARE и NO KEY UPDATE совместимы.
```

###  Пример 6 SELECT, LOCK, ALTER и фраза NOWAIT

<!-- Команда немедленно завершается с ошибкой, если ресурс оказался занят. В прикладном коде такую ошибку можно перехватить и обработать. -->

```sql
-- Session #1
sudo -u postgres psql
\c locks
BEGIN;
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;

-- Session #2
sudo -u postgres psql
\c locks
SELECT * FROM accounts FOR UPDATE NOWAIT;

-- Session #3 
sudo -u postgres psql
\c locks

-- Есть еще один вариант не ждать — использовать команду SELECT FOR с фразой SKIP LOCKED. Такая команда будет пропускать заблокированные строки, но обрабатывать свободные.
BEGIN;
DECLARE c CURSOR FOR SELECT * FROM accounts ORDER BY acc_no FOR UPDATE SKIP LOCKED;
FETCH c;

-- Session #1
ROLLBACK;

-- Session #2
ROLLBACK;
```

##  Блокировки других объектов

###  Пример 1 Пример взаимоблокировки


```sql
-- Session #1
sudo -u postgres psql
\c locks
-- Параметры
SHOW deadlock_timeout;
SHOW lock_timeout;

-- Простой пример. Первая транзакция намерена перенести 100 рублей с первого счета на второй. Для этого она сначала уменьшает первый счет
BEGIN;
UPDATE accounts SET amount = amount - 100.00 WHERE acc_no = 1;

-- Session #2
sudo -u postgres psql
\c locks
-- В это же время вторая транзакция намерена перенести 10 рублей со второго счета на первый. Она начинает с того, что уменьшает второй счет:
BEGIN;
UPDATE accounts SET amount = amount - 10.00 WHERE acc_no = 2;

-- Session #1
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 2;

-- Session #2
UPDATE accounts SET amount = amount + 10.00 WHERE acc_no = 1;
-- Возникает циклическое ожидание, который никогда не завершится само по себе. Через секунду первая транзакция, не получив доступ к ресурсу, инициирует проверку взаимоблокировки и обрывается сервером.

ROLLBACK;

-- Session #1
ROLLBACK;
```

###  Пример 2 Пример блокировка не-отношений
<!-- Таким ресурсом может быть почти все, что угодно: табличные пространства, подписки, схемы, роли, перечислимые типы данных… Грубо говоря все, что только можно найти в системном каталоге. -->

```sql
-- Session #1
sudo -u postgres psql
\c locks
BEGIN;
CREATE TABLE example(n integer);

SELECT
  database,
  (SELECT datname FROM pg_database WHERE oid = l.database) AS dbname,
  classid,
  (SELECT relname FROM pg_class WHERE oid = l.classid) AS classname,
  objid,
  mode,
  granted
FROM pg_locks l
WHERE l.locktype = 'object' AND l.pid = pg_backend_pid();

SELECT rolname FROM pg_authid WHERE oid = 16384;

SELECT nspname FROM pg_namespace WHERE oid = 2200;

ROLLBACK;
```

###  Пример 3 Пример рекомендательных блокировок (advisory locks)
```sql
-- Session #1
sudo -u postgres psql
\c locks

-- Допустим, у нас есть условный ресурс, не соответствующий никакому объекту базы данных (который мы могли бы заблокировать командами типа SELECT FOR или LOCK TABLE). Нужно придумать для него числовой идентификатор. Если у ресурса есть уникальное имя, то простой вариант — взять от него хеш-код
SELECT hashtext('пример');

-- захватываем блокировку
BEGIN;
SELECT pg_advisory_lock(hashtext('пример'));

SELECT locktype, objid, mode, granted 
FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid();

-- В приведенном примере блокировка действует до конца сеанса, а не транзакции, как обычно.
COMMIT;
SELECT locktype, objid, mode, granted 
FROM pg_locks WHERE locktype = 'advisory' AND pid = pg_backend_pid();

SELECT pg_advisory_unlock(hashtext('пример'));

-- Session #2
sudo -u postgres psql
\c locks
SELECT locktype, objid, mode, granted FROM pg_locks WHERE locktype = 'advisory'

-- Session #1
exit

-- Session #2
SELECT locktype, objid, mode, granted FROM pg_locks WHERE locktype = 'advisory'
```


