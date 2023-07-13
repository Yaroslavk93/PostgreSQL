# **Механизм блокировок**

## **Цель:**
### - приобрести понимать, как работает механизм блокировок объектов и строк.

------------

1. Настройте сервер так, чтобы в журнал сообщений сбрасывалась информация о блокировках, удерживаемых более 200 миллисекунд. Воспроизведите ситуацию, при которой в журнале появятся такие сообщения.
- *Запускаем ВМ (разворачивал в Oracle VM, используя Vagrant):*
```bash
vagrant up
```
- *Конфиг ВМ*
```bash
Vagrant.configure("2") do |config|

  config.vm.box = "ubuntu/focal64"

  config.vm.provider "virtualbox" do |v|
    v.memory = 4096  # ОЗУ
    v.cpus = 2  # ядра
  end
  
  # Конфигурация диска
  config.vm.disk :disk, size: "10GB", primary: true

  # Скрипт для установки PostgreSQL
  config.vm.provision "shell", inline: <<-SHELL
    sudo apt-get update
    sudo apt-get install -y wget ca-certificates
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
    echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" |sudo tee  /etc/apt/sources.list.d/pgdg.list
    sudo apt-get update
    sudo apt-get install -y postgresql-15
  SHELL

end
```
- *Заходим в базу под пользователем postgres:*
```bash
sudo -i -u postgres psql 
```
- *Создадим тестовую базу, схему и таблицу*
```sql
CREATE DATABASE mytestdb;
CREATE SCHEMA testnm;
CREATE TABLE testnm.persons(id SERIAL, first_name TEXT, second_name TEXT);
INSERT INTO testnm.persons(first_name, second_name) VALUES('ivan', 'ivanov');
INSERT INTO testnm.persons(first_name, second_name) VALUES('petr', 'petrov');
```

- *Далее настроим сервер PostgreSQL, чтобы в журнал сообщений сбрасывалась информация о блокировках, удерживаемых более 200 мс.*
```sql
ALTER SYSTEM SET log_lock_waits = on; -- Включаем логирование событий, когда сессия ждет блокировку дольше чем deadlock_timeout.
ALTER SYSTEM SET deadlock_timeout = '200ms'; -- Устанавливаем время ожидания блокировки на 200 мс.
SELECT pg_reload_conf(); -- Применяем изменения без перезагрузки сервера.
```
- *Проверяем логи*

```bash
sudo tail -n 100 /var/log/postgresql/postgresql-15-main.log

2023-07-12 17:20:47.333 UTC [778] LOG:  received SIGHUP, reloading configuration files
2023-07-12 17:20:47.334 UTC [778] LOG:  parameter "log_lock_waits" changed to "on"
2023-07-12 17:20:47.334 UTC [778] LOG:  parameter "deadlock_timeout" changed to "200ms"
```
- *Воспроизводим ситуацию, при которой в журнале появятся сообщения о блокировках, удерживаемых более 200 миллисекунд.*
*Сначала мы должны задать настройки в pg_hba и postgresql.conf для подключения к базе*
```bash
sudo nano /etc/postgresql/15/main/pg_hba.conf

host    mytestdb    postgres    *.*.*.*/*    scram-sha-256
``````
```bash
sudo nano /etc/postgresql/15/main/postgresql.conf

listen_addresses = '*'
```
*На локальной машине задаём путь до переменной для удобства запуска psql из командной строки*
```bash
setx /M PATH "%PATH%;C:\Program Files\PostgreSQL\14\bin"
``````
*Подключаемся к базе и начинаем несколько сессий*
```bash
psql -h  localhost -d mytestdb -U postgres
``````
*Воспроизводим ситуацию*
```sql
psql_1:
BEGIN;
UPDATE testnm.persons SET first_name = 'ivan_updated' WHERE id = 1;
``````
```sql
psql_2:
BEGIN;
UPDATE testnm.persons SET first_name = 'ivan_updated_again' WHERE id = 1;
``````
```bash
sudo tail -n 100 /var/log/postgresql/postgresql-15-main.log

2023-07-13 11:35:37.085 UTC [63524] postgres@mytestdb LOG:  process 63524 still waiting for ShareLock on transaction 2261209 after 200.599 ms
2023-07-13 11:35:37.085 UTC [63524] postgres@mytestdb DETAIL:  Process holding the lock: 72806. Wait queue: 63524.
2023-07-13 11:35:37.085 UTC [63524] postgres@mytestdb CONTEXT:  while updating tuple (0,1) in relation "persons"
2023-07-13 11:35:37.085 UTC [63524] postgres@mytestdb STATEMENT:  UPDATE testnm.persons SET first_name = 'ivan_updated_again' WHERE id = 1;

``````

*Полученный лог нам говорит следующее:*  
a) Процесс с идентификатором 63524 ждет блокировки ShareLock на транзакции с идентификатором 2261209 уже более 200 миллисекунд.  
b) Процесс, который удерживает эту блокировку, имеет идентификатор 72806.  
c) Эта блокировка возникла во время попытки обновления кортежа (0,1) в таблице persons.  
d) SQL-запрос, который вызвал эту блокировку, был: UPDATE testnm.persons SET first_name = 'ivan_updated_again' WHERE id = 1;  

---------------

2. Смоделируйте ситуацию обновления одной и той же строки тремя командами UPDATE в разных сеансах. Изучите возникшие блокировки в представлении pg_locks и убедитесь, что все они понятны. Пришлите список блокировок и объясните, что значит каждая.
- *По аналогии с 1-ым заданием, моделируем ситуацию блокировок*
```sql
psql_1: UPDATE testnm.persons SET first_name = 'petr_up1' WHERE id = 2;
psql_2: UPDATE testnm.persons SET first_name = 'petr_up2' WHERE id = 2;
psql_3: UPDATE testnm.persons SET first_name = 'petr_up3' WHERE id = 2;
```
- *Получаем лог*
```bash
sudo tail -n 100 /var/log/postgresql/postgresql-15-main.log

2023-07-13 11:49:41.672 UTC [63524] postgres@mytestdb LOG:  process 63524 still waiting for ShareLock on transaction 2261211 after 209.731 ms
2023-07-13 11:49:41.672 UTC [63524] postgres@mytestdb DETAIL:  Process holding the lock: 72806. Wait queue: 63524.
2023-07-13 11:49:41.672 UTC [63524] postgres@mytestdb CONTEXT:  while updating tuple (0,2) in relation "persons"
2023-07-13 11:49:41.672 UTC [63524] postgres@mytestdb STATEMENT:  UPDATE testnm.persons SET first_name = 'petr_up2' WHERE id = 2;
2023-07-13 11:50:26.943 UTC [73179] postgres@mytestdb LOG:  process 73179 still waiting for ExclusiveLock on tuple (0,2) of relation 24919 of database 16388 after 200.746 ms
2023-07-13 11:50:26.943 UTC [73179] postgres@mytestdb DETAIL:  Process holding the lock: 63524. Wait queue: 73179.
2023-07-13 11:50:26.943 UTC [73179] postgres@mytestdb STATEMENT:  UPDATE testnm.persons SET first_name = 'petr_up3' WHERE id = 2;
``````
*Сообщения в журнале говорят о том, что:*  
1) 11:49:41.672 - Процесс с ID 63524 ждет блокировки ShareLock на транзакции с ID 2261211 уже более 209 миллисекунд. Блокировка удерживается процессом с ID 72806. Блокировка возникла во время обновления кортежа (0,2) в таблице persons. Запрос, вызвавший блокировку: UPDATE testnm.persons SET first_name = 'petr_up2' WHERE id = 2;  
2) 11:50:26.943 - Процесс с ID 73179 ждет ExclusiveLock на кортеж (0,2) отношения с ID 24919 базы данных с ID 16388 уже более 200 миллисекунд. Эта блокировка удерживается процессом с ID 63524. Запрос, вызвавший блокировку: UPDATE testnm.persons SET first_name = 'petr_up3' WHERE id = 2;  
    
*В первом случае процесс 63524 ждет, пока процесс 72806 освободит блокировку и позволит ему обновить строку с ID = 2 в таблице persons.*  
*Во втором случае, процесс 73179 ждет, пока процесс 63524 освободит ExclusiveLock и позволит ему обновить ту же строку в таблице persons.*  
*Это повторение сценария, в котором два или более процесса пытаются обновить одну и ту же строку в базе данных, приводя к ожиданию освобождения блокировки.*

- *Делаем COMMIT и проверяем логи;*

```bash
sudo tail -n 100 /var/log/postgresql/postgresql-15-main.log

2023-07-13 12:02:02.301 UTC [63524] postgres@mytestdb LOG:  process 63524 acquired ShareLock on transaction 2261211 after 740839.184 ms
2023-07-13 12:02:02.301 UTC [63524] postgres@mytestdb CONTEXT:  while updating tuple (0,2) in relation "persons"
2023-07-13 12:02:02.301 UTC [63524] postgres@mytestdb STATEMENT:  UPDATE testnm.persons SET first_name = 'petr_up2' WHERE id = 2;
2023-07-13 12:02:02.302 UTC [73179] postgres@mytestdb LOG:  process 73179 acquired ExclusiveLock on tuple (0,2) of relation 24919 of database 16388 after 695560.348 ms
2023-07-13 12:02:02.302 UTC [73179] postgres@mytestdb STATEMENT:  UPDATE testnm.persons SET first_name = 'petr_up3' WHERE id = 2;
2023-07-13 12:02:02.503 UTC [73179] postgres@mytestdb LOG:  process 73179 still waiting for ShareLock on transaction 2261212 after 200.826 ms
2023-07-13 12:02:02.503 UTC [73179] postgres@mytestdb DETAIL:  Process holding the lock: 63524. Wait queue: 73179.
2023-07-13 12:02:02.503 UTC [73179] postgres@mytestdb CONTEXT:  while rechecking updated tuple (0,9) in relation "persons"
2023-07-13 12:02:02.503 UTC [73179] postgres@mytestdb STATEMENT:  UPDATE testnm.persons SET first_name = 'petr_up3' WHERE id = 2;
2023-07-13 12:02:11.746 UTC [63446] LOG:  checkpoint starting: time
2023-07-13 12:02:11.865 UTC [63446] LOG:  checkpoint complete: wrote 2 buffers (0.0%); 0 WAL file(s) added, 0 removed, 0 recycled; write=0.111 s, sync=0.007 s, total=0.120 s; sync files=2, longest=0.006 s, average=0.004 s; distance=0 kB, estimate=0 kB
2023-07-13 12:02:13.046 UTC [73179] postgres@mytestdb LOG:  process 73179 acquired ShareLock on transaction 2261212 after 10743.429 ms
2023-07-13 12:02:13.046 UTC [73179] postgres@mytestdb CONTEXT:  while rechecking updated tuple (0,9) in relation "persons"
2023-07-13 12:02:13.046 UTC [73179] postgres@mytestdb STATEMENT:  UPDATE testnm.persons SET first_name = 'petr_up3' WHERE id = 2;
``````

*12:02:02.301 - Процесс с ID 63524 получил ShareLock на транзакции с ID 2261211 после ожидания 740839 миллисекунд. Это произошло во время обновления кортежа (0,2) в таблице persons командой UPDATE testnm.persons SET first_name = 'petr_up2' WHERE id = 2;*  

*12:02:02.302 - Процесс с ID 73179 получил ExclusiveLock на кортеж (0,2) отношения с ID 24919 базы данных с ID 16388 после ожидания 695560 миллисекунд. Это произошло в результате выполнения команды UPDATE testnm.persons SET first_name = 'petr_up3' WHERE id = 2;* 

*12:02:02.503 - Процесс с ID 73179 продолжает ожидать ShareLock на транзакции с ID 2261212 уже более 200 миллисекунд. Этот замок удерживает процесс с ID 63524. Это произошло во время повторной проверки обновленного кортежа (0,9) в таблице persons командой UPDATE testnm.persons SET first_name = 'petr_up3' WHERE id = 2;*  

*12:02:13.046 - Процесс с ID 73179 получил ShareLock на транзакции с ID 2261212 после ожидания 10743 миллисекунд. Это произошло во время повторной проверки обновленного кортежа (0,9) в таблице persons командой UPDATE testnm.persons SET first_name = 'petr_up3' WHERE id = 2;*  
  
Кроме того, в 12:02:11.746 и 12:02:11.865 произошли начало и окончание процесса контрольной точки.
  
Эти логи говорят о том, что процессы 63524 и 73179 продолжают взаимодействовать, обновляя одну и ту же строку в таблице persons и ожидая, когда другой процесс освободит блокировку. Блокировки, которые здесь обсуждаются, — это механизмы, которые обеспечивают целостность данных при конкурентном доступе к данным.

-----------------

3. Воспроизведите взаимоблокировку трех транзакций. Можно ли разобраться в ситуации постфактум, изучая журнал сообщений?

- *Открываем 3 сессии, чтобы смоделировать ситуацию с взаимоблокировками*  
  
*В Сессии 1 выполняем следующие команды:*
**psql_1**
```sql
BEGIN;
UPDATE testnm.persons SET first_name = 'ivan_1' WHERE id = 1;
``````
  
*В Сессии 2 выполняем следующие команды:*
**psql_2**
```sql
BEGIN;
UPDATE testnm.persons SET first_name = 'petr_2' WHERE id = 2;
UPDATE testnm.persons SET first_name = 'ivan_2' WHERE id = 1;
``````
На этом этапе Сессия 2 будет ждать, пока Сессия 1 не завершит свою транзакцию, так как Сессия 1 блокирует запись с id = 1.  
  
*Теперь перейдём к Сессии 3 и выполним следующие команды:*
**psql_3**
```sql
BEGIN;
UPDATE testnm.persons SET first_name = 'petr_3' WHERE id = 2;
``````
Сессия 3 будет ждать, пока Сессия 2 не завершит свою транзакцию, так как Сессия 2 блокирует запись с id = 2.  
  
*Возвращаемся к Сессии 1 и попробуем выполнить следующую команду:*
**psql_1**
```sql
UPDATE testnm.persons SET first_name = 'petr_1' WHERE id = 2;

ERROR:  deadlock detected
ПОДРОБНОСТИ:  Process 73179 waits for ExclusiveLock on tuple (0,11) of relation 24919 of database 16388; blocked by process 63524.
Process 63524 waits for ShareLock on transaction 2261224; blocked by process 72806.
Process 72806 waits for ShareLock on transaction 2261223; blocked by process 73179.
ПОДСКАЗКА:  See server log for query details.
``````
Теперь Сессия 1 пытается обновить запись с id = 2, но она блокирована Сессией 2, которая, в свою очередь, ждет Сессию 1. Это и есть взаимоблокировка. После истечения deadlock_timeout PostgreSQL должен автоматически прервать одну из транзакций и зарегистрировать это в журнале.  
```bash
sudo tail -n 100 /var/log/postgresql/postgresql-15-main.log

2023-07-13 15:44:11.799 UTC [73179] postgres@mytestdb ERROR:  deadlock detected
2023-07-13 15:44:11.799 UTC [73179] postgres@mytestdb DETAIL:  Process 73179 waits for ExclusiveLock on tuple (0,11) of relation 24919 of database 16388; blocked by process 63524.
        Process 63524 waits for ShareLock on transaction 2261224; blocked by process 72806.
        Process 72806 waits for ShareLock on transaction 2261223; blocked by process 73179.
        Process 73179: UPDATE testnm.persons SET first_name = 'petr_1' WHERE id = 2;
        Process 63524: UPDATE testnm.persons SET first_name = 'petr_3' WHERE id = 2;
        Process 72806: UPDATE testnm.persons SET first_name = 'ivan_2' WHERE id = 1;
2023-07-13 15:44:11.799 UTC [73179] postgres@mytestdb HINT:  See server log for query details.
2023-07-13 15:44:11.799 UTC [73179] postgres@mytestdb STATEMENT:  UPDATE testnm.persons SET first_name = 'petr_1' WHERE id = 2;
2023-07-13 15:44:11.800 UTC [72806] postgres@mytestdb LOG:  process 72806 acquired ShareLock on transaction 2261223 after 26873.166 ms
2023-07-13 15:44:11.800 UTC [72806] postgres@mytestdb CONTEXT:  while updating tuple (0,8) in relation "persons"
2023-07-13 15:44:11.800 UTC [72806] postgres@mytestdb STATEMENT:  UPDATE testnm.persons SET first_name = 'ivan_2' WHERE id = 1;
2023-07-13 15:44:23.440 UTC [63446] LOG:  checkpoint starting: time
2023-07-13 15:44:23.548 UTC [63446] LOG:  checkpoint complete: wrote 2 buffers (0.0%); 0 WAL file(s) added, 0 removed, 0 recycled; write=0.105 s, sync=0.001 s, total=0.109 s; sync files=2, longest=0.001 s, average=0.001 s; distance=1 kB, estimate=1 kB
2023-07-13 15:50:15.192 UTC [63524] postgres@mytestdb LOG:  process 63524 acquired ShareLock on transaction 2261224 after 381066.932 ms
2023-07-13 15:50:15.192 UTC [63524] postgres@mytestdb CONTEXT:  while updating tuple (0,11) in relation "persons"
2023-07-13 15:50:15.192 UTC [63524] postgres@mytestdb STATEMENT:  UPDATE testnm.persons SET first_name = 'petr_3' WHERE id = 2;
2023-07-13 15:50:23.854 UTC [63446] LOG:  checkpoint starting: time
2023-07-13 15:50:23.970 UTC [63446] LOG:  checkpoint complete: wrote 2 buffers (0.0%); 0 WAL file(s) added, 0 removed, 0 recycled; write=0.113 s, sync=0.001 s, total=0.117 s; sync files=2, longest=0.001 s, average=0.001 s; distance=1 kB, estimate=1 kB
`````` 
*По этому выводу видно, что произошла взаимная блокировка (deadlock) между тремя процессами с ID 73179, 63524 и 72806.*  
a) Процесс 73179 ожидает эксклюзивной блокировки (ExclusiveLock) на кортеж (0,11) в отношении 24919 базы данных 16388. Эта блокировка блокируется процессом 63524.  
b) Процесс 63524 в свою очередь ждет блокировку на уровне транзакции (ShareLock) на транзакцию 2261224. Эта блокировка блокируется процессом 72806.  
c) Процесс 72806 также ждет блокировку на уровне транзакции (ShareLock) на транзакцию 2261223. Эта блокировка блокируется процессом 73179.  
  
Таким образом, образовался цикл взаимных блокировок.  
PostgreSQL детектирует такие ситуации и автоматически прерывает одну из транзакций, чтобы разрешить взаимоблокировку. В данном случае, была прервана транзакция процесса 73179.

----------------------

4. Могут ли две транзакции, выполняющие единственную команду UPDATE одной и той же таблицы (без where), заблокировать друг друга?  
Задание со звездочкой*
Попробуйте воспроизвести такую ситуацию.
  
Как правило, если две транзакции выполняют команду UPDATE одной и той же таблицы без условия WHERE, то они не должны блокировать друг друга, поскольку PostgreSQL использует механизм MVCC (Multi-Version Concurrency Control), который позволяет создавать "снимки" данных для каждой транзакции, поэтому каждая транзакция работает с собственной версией данных.  
  
Однако, в редких случаях может возникнуть блокировка из-за того, что одна транзакция уже обновила данные и ожидает своего завершения, а другая транзакция пытается обновить те же самые данные.  
  
Тем не менее, в целом, две такие транзакции не должны блокировать друг друга, и эту ситуацию будет довольно сложно воспроизвести, так как это потребует точного тайминга между выполнением этих двух транзакций.    
    
Приведем пример двух таких транзакций, которые можно попытаться выполнить параллельно:
**psql_1**
```sql
BEGIN;
UPDATE testnm.persons SET first_name = 'ivan_updated';
-- COMMIT;
``````
**psql_2**
```sql
BEGIN;
UPDATE testnm.persons SET first_name = 'petr_updated';
-- COMMIT;
``````
- *Посмотрим события в pg_stat_activity*
```sql
SELECT pid, wait_event_type, wait_event, query 
FROM pg_stat_activity 
WHERE wait_event IS NOT NULL;
``````
  pid  | wait_event_type |     wait_event      |            query
-------|-----------------|---------------------|-----------------------------------------------------
 63450 | Activity        | AutoVacuumMain      |
 63451 | Activity        | LogicalLauncherMain |
 72806 | Lock            | transactionid       | UPDATE testnm.persons SET first_name = 'petr_updated';
 73179 | Client          | ClientRead          | UPDATE testnm.persons SET first_name = 'ivan_updated';
 63447 | Activity        | BgWriterHibernate   |
 63446 | Activity        | CheckpointerMain    |
 63449 | Activity        | WalWriterMain       |
  
Здесь мы видим два процесса (с PID 72806 и 73179), которые выполняют запросы UPDATE. Обратите внимание, что процесс с PID 72806 ожидает захвата блокировки (Lock), причем источником блокировки является транзакция (transactionid). Это может означать, что процесс находится в состоянии ожидания, пока другой процесс не завершит свою транзакцию.  
  
В то же время, процесс с PID 73179 ожидает чтение от клиента (ClientRead), что обычно означает, что процесс ожидает дополнительные данные от клиента.  
  
Таким образом, мы видим, что вторая транзакция (с PID 72806) ожидает завершения первой транзакции. Это происходит из-за того, что оба запроса пытаются обновить все строки в одной и той же таблице одновременно.