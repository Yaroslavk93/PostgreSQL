# **Работа с журналами**

## **Цель:**
### - уметь работать с журналами и контрольными точками;
### - уметь настраивать параметры журналов.

----------

1. Настройте выполнение контрольной точки раз в 30 секунд:
- *Для этого необходимо внести изсенения в файл конфигурации postgresql.conf*
```bash
sudo nano /etc/postgresql/15/main/postgresql.conf
```
- *Вносим изменения*
```ruby
checkpoint_timeout = 30s
```
- *Перезапускаем кластер*
```bash
systemctl restart postgresql
```

-----------

2. 10 минут c помощью утилиты pgbench подавайте нагрузку:
```bash
sudo -u postgres pgbench -c8 -P 6 -T 600 -U postgres mytestdb
```
- *вывод на экран:*
```bash
pgbench (15.3 (Ubuntu 15.3-1.pgdg20.04+1))
starting vacuum...end.
progress: 6.0 s, 1057.0 tps, lat 7.534 ms stddev 5.011, 0 failed
progress: 12.0 s, 1074.4 tps, lat 7.432 ms stddev 5.040, 0 failed
progress: 18.0 s, 1074.8 tps, lat 7.429 ms stddev 4.961, 0 failed
...
progress: 582.0 s, 1135.5 tps, lat 7.029 ms stddev 4.423, 0 failed
progress: 588.0 s, 1096.7 tps, lat 7.285 ms stddev 5.049, 0 failed
progress: 594.0 s, 1103.3 tps, lat 7.239 ms stddev 4.679, 0 failed
progress: 600.0 s, 1108.9 tps, lat 7.199 ms stddev 4.878, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 8
number of threads: 1
maximum number of tries: 1
duration: 600 s
number of transactions actually processed: 659283
number of failed transactions: 0 (0.000%)
latency average = 7.267 ms
latency stddev = 4.792 ms
initial connection time = 12.616 ms
tps = 1098.799572 (without initial connection time)
```

----------

3. Измерьте, какой объем журнальных файлов был сгенерирован за это время. Оцените, какой объем приходится в среднем на одну контрольную точку.
- *Объём журнала*
```bash
du -sh /var/lib/postgresql/15/main/pg_wal

2.1G    /var/lib/postgresql/15/main/pg_wal
```
- *Средний объём на одну контрольную точку:*
```
~ 105 MB на одну точку (Тест работал 600 секунд, делим на 30 секун - время срабатывания контрольной точки = 20. Далее общий объём 2100 GB делим на 20 - количество контрольных точек)
```

--------

4. Проверьте данные статистики: все ли контрольные точки выполнялись точно по расписанию. Почему так произошло?
- *Для проверки сколько контрольных точек было создано за заданный интерва (30 секунд), для начала я замерил их общее количество*
```sql
SELECT checkpoints_timed, checkpoints_req FROM pg_stat_bgwriter;

 checkpoints_timed | checkpoints_req
-------------------+-----------------
              1047 |               2
```
- *Далее я запустил тест по новой, для того чтобы проверить количство созданных новых точек:*
```bash
sudo -u postgres pgbench -c8 -P 6 -T 600 -U postgres mytestdb
```
- *Вновь проверяем количество созданных точек:*
```sql
SELECT checkpoints_timed, checkpoints_req FROM pg_stat_bgwriter;

 checkpoints_timed | checkpoints_req
-------------------+-----------------
              1069 |               2

```
- *С учётом заданного интервала (30 секунд), учитывая время для выхода из psql и повторного запуска теста, я прихожу к выводу, что количество созданных точек соответствует действительности - 20 точек (тест на 600 секунд \ интервал 30 секунд = 20 контрольных точек)*

-------------

5. Сравните tps в синхронном/асинхронном режиме утилитой pgbench. Объясните полученный результат.
- *Делаем тест в синхронном режиме:*
```bash
sudo -u postgres pgbench -P 1 -T 10 -U postgres mytestdb

pgbench (15.3 (Ubuntu 15.3-1.pgdg20.04+1))
starting vacuum...end.
progress: 1.0 s, 383.9 tps, lat 2.596 ms stddev 0.644, 0 failed
progress: 2.0 s, 929.1 tps, lat 1.075 ms stddev 0.957, 0 failed
progress: 3.0 s, 1747.3 tps, lat 0.572 ms stddev 0.357, 0 failed
progress: 4.0 s, 1770.0 tps, lat 0.564 ms stddev 0.325, 0 failed
progress: 5.0 s, 1814.2 tps, lat 0.551 ms stddev 0.046, 0 failed
progress: 6.0 s, 1786.7 tps, lat 0.559 ms stddev 0.253, 0 failed
progress: 7.0 s, 1805.2 tps, lat 0.553 ms stddev 0.046, 0 failed
progress: 8.0 s, 1786.8 tps, lat 0.560 ms stddev 0.051, 0 failed
progress: 9.0 s, 1765.2 tps, lat 0.566 ms stddev 0.252, 0 failed
progress: 10.0 s, 1784.8 tps, lat 0.560 ms stddev 0.047, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 1
number of threads: 1
maximum number of tries: 1
duration: 10 s
number of transactions actually processed: 15574
number of failed transactions: 0 (0.000%)
latency average = 0.642 ms
latency stddev = 0.467 ms
initial connection time = 2.800 ms
tps = 1557.768256 (without initial connection time)
```
- *Изменяем настройку конфигурации и отключаем синхронный режим:*
```sql
ALTER SYSTEM SET synchronous_commit = off;
SELECT pg_reload_conf(); -- перечитываем конфигурацию

SHOW synchronous_commit;
 synchronous_commit
--------------------
 off
(1 row)
```
- *Перезагружаем кластер:*
```bash
systemctl restart postgresql
```
- *Запускаем тест в асинхронном режиме:*
```bash
sudo -u postgres pgbench -P 1 -T 10 -U postgres mytestdb

pgbench (15.3 (Ubuntu 15.3-1.pgdg20.04+1))
starting vacuum...end.
progress: 1.0 s, 962.0 tps, lat 1.037 ms stddev 0.977, 0 failed
progress: 2.0 s, 433.9 tps, lat 2.303 ms stddev 0.317, 0 failed
progress: 3.0 s, 440.1 tps, lat 2.272 ms stddev 0.282, 0 failed
progress: 4.0 s, 438.8 tps, lat 2.278 ms stddev 0.223, 0 failed
progress: 5.0 s, 438.0 tps, lat 2.283 ms stddev 0.214, 0 failed
progress: 6.0 s, 415.0 tps, lat 2.407 ms stddev 0.288, 0 failed
progress: 7.0 s, 457.1 tps, lat 2.190 ms stddev 0.213, 0 failed
progress: 8.0 s, 430.0 tps, lat 2.326 ms stddev 0.371, 0 failed
progress: 9.0 s, 579.1 tps, lat 1.725 ms stddev 0.911, 0 failed
progress: 10.0 s, 454.9 tps, lat 2.196 ms stddev 0.280, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 1
number of threads: 1
maximum number of tries: 1
duration: 10 s
number of transactions actually processed: 5050
number of failed transactions: 0 (0.000%)
latency average = 1.980 ms
latency stddev = 0.757 ms
initial connection time = 1.660 ms
tps = 505.010201 (without initial connection time)
```

- *Не смотря на то, что асинхронный режим должен отрабатывать намного быстрее, ввиду отсутствия необходимости ожидать подтверждения каждой операции от сервера перед выполнением следующей - результаты показали, что в синхронном режиме PostgreSQL обрабатывает больше транзакций в секунду (tps, transactions per second) и имеет более низкую среднюю задержку (latency average) по сравнению с асинхронным режимом.*

---------------

6. Создайте новый кластер с включенной контрольной суммой страниц. Создайте таблицу. Вставьте несколько значений. Выключите кластер. Измените пару байт в таблице. Включите кластер и сделайте выборку из таблицы. Что и почему произошло? как проигнорировать ошибку и продолжить работу?
- *Добавляем initdb в $PATH*
```bash
export PATH=$PATH:/usr/lib/postgresql/15/bin/
```
- *Создаём новый кластер в ключенной контрольной суммой:*
```bash
sudo -u postgres /usr/lib/postgresql/15/bin/initdb --data-checksums /etc/postgresql/new_cluster

The files belonging to this database system will be owned by user "postgres".
This user must also own the server process.

The database cluster will be initialized with locale "C.UTF-8".
The default database encoding has accordingly been set to "UTF8".
The default text search configuration will be set to "english".

Data page checksums are enabled.

creating directory /etc/postgresql/new_cluster ... ok
creating subdirectories ... ok
selecting dynamic shared memory implementation ... posix
selecting default max_connections ... 100
selecting default shared_buffers ... 128MB
selecting default time zone ... Etc/UTC
creating configuration files ... ok
running bootstrap script ... ok
performing post-bootstrap initialization ... ok
syncing data to disk ... ok

initdb: warning: enabling "trust" authentication for local connections
initdb: hint: You can change this by editing pg_hba.conf or using the option -A, or --auth-local and --auth-host, the next time you run initdb.

Success. You can now start the database server using:

    /usr/lib/postgresql/15/bin/pg_ctl -D /etc/postgresql/new_cluster -l logfile start

```
- *Меняем порт для подключения к новому кластеру*
```bash
sudo nano /etc/postgresql/new_cluster/postgresql.conf

port = 5433
```
- *Запускаем новый кластер*
```bash
sudo -u postgres /usr/lib/postgresql/15/bin/pg_ctl -D /etc/postgresql/new_cluster -l /var/log/postgresql/new_cluster.log start
```
- *Создаём новую базу и подключаемся к новому кластеру*
```bash
createdb -h localhost -p 5433 -U postgres mytestdb
psql -h localhost -p 5433 -U postgres -d mytestdb
```
- *Создаём таблицу и вставляем несколько значений*
```sql
CREATE TABLE my_table (id int primary key, value text);
INSERT INTO my_table VALUES (1, 'one'), (2, 'two'), (3, 'three');
```
- *Получаем путь для необходимого файла*
```sql
SELECT pg_relation_filepath('my_table');
 pg_relation_filepath
----------------------
 base/16388/16389
(1 row)
```
- *Выключаем новый кластер*
```bash
sudo -u postgres /usr/lib/postgresql/15/bin/pg_ctl -D /etc/postgresql/new_cluster stop
```
- *Меняем пару байт в таблице*
```bash
sudo dd if=/dev/urandom of=/etc/postgresql/new_cluster/base/16388/16389 bs=1 count=1 seek=10 conv=notrunc

conv=notrunc
1+0 records in
1+0 records out
1 byte copied, 0.000187562 s, 5.3 kB/s


if=/dev/urandom указывает источник данных (в этом случае случайные данные).
of=of=/etc/postgresql/new_cluster/base/16388/16389 указывает файл, в который будут записаны данные.
bs=1 задает размер блока в 1 байт.
count=1 указывает, что будет записан только один блок.
seek=10 перемещается на 10 байтов в файле перед записью данных.
conv=notrunc указывает, что файл не должен быть усечен перед записью данных.
```
- *Включаем нужный кластер и подключаемся к базе*
```bash
sudo -u postgres /usr/lib/postgresql/15/bin/pg_ctl -D /etc/postgresql/new_cluster -l /var/log/postgresql/new_cluster.log start

psql -h localhost -p 5433 -U postgres -d mytestdb
```
- *Пробуем сделать выборку из таблицы*
```sql
SELECT * FROM my_table;

WARNING:  page verification failed, calculated checksum 4685 but expected 5009
ERROR:  invalid page in block 0 of relation base/16388/16389
```
*Мы получили ошибку, сообщающую о неконсистентности данных из-за повреждения файла таблицы. Для того, чтобы продолжить работу мы можем принудительно отключить проверку контрольной суммы, однако это может привести к дальнейшем проблемам, включая потерю данных и нестабильную работу кластера*

```sql
ALTER SYSTEM SET ignore_checksum_failure = on;
mytestdb=# SELECT pg_reload_conf();
```
- *Пытался восстановить данные путём создания дампа поврежённой таблицы, к сожалению не удалось.*
```bash
sudo -u postgres pg_dump -h localhost -p 5433 -t my_table -f /tmp/my_table.sql -d mytestdb
```
*Получил ошибку, что PostgreSQL не может прочитать данные из таблицы*
```bash
pg_dump: error: connection to server on socket "/var/run/postgresql/.s.PGSQL.5432" failed: FATAL:  Peer authentication failed for user "postgres"
root@ubuntu-focal:/home/vagrant# ^C
root@ubuntu-focal:/home/vagrant# sudo -u postgres pg_dump -h localhost -p 5433 -t my_table -f my_table.sql -d mytestdb
pg_dump: error: could not open output file "my_table.sql": Permission denied
root@ubuntu-focal:/home/vagrant# ^C
root@ubuntu-focal:/home/vagrant# sudo -u postgres pg_dump -h localhost -p 5433 -t my_table -f /tmp/my_table.sql -d mytestdb
2023-07-09 21:18:10.699 UTC [5656] WARNING:  page verification failed, calculated checksum 4685 but expected 5009
2023-07-09 21:18:10.700 UTC [5656] ERROR:  invalid page in block 0 of relation base/16388/16389
2023-07-09 21:18:10.700 UTC [5656] STATEMENT:  COPY public.my_table (id, value) TO stdout;
pg_dump: error: Dumping the contents of table "my_table" failed: PQgetResult() failed.
pg_dump: detail: Error message from server: ERROR:  invalid page in block 0 of relation base/16388/16389
pg_dump: detail: Command was: COPY public.my_table (id, value) TO stdout;
```
- *Так же пытался восстановить данные путём сброса WAL*
```bash
sudo -u postgres /usr/lib/postgresql/15/bin/pg_resetwal /etc/postgresql/new_cluster
```

