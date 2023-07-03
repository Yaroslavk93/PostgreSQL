# **Настройка autovacuum с учетом особеностей производительности**
  
## **Цель:**
### - запустить нагрузочный тест pgbench;
### - настроить параметры autovacuum;
### - проверить работу autovacuum.

---

1. Создать инстанс ВМ с 2 ядрами и 4 Гб ОЗУ и SSD 10GB
```bash
vagrant init ubuntu/focal64
```
- *Параметры ВМ:*
```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/focal64" 

  config.vm.provider "virtualbox" do |v|
    v.memory = 4096  # ОЗУ
    v.cpus = 2  # ядра
  end

  # Конфигурация диска SSD
  config.vm.disk :disk, size: "10GB", primary: true

end
```
- *Запускаем машину*
```bash
vagrant up
```

---

2. Установить на него PostgreSQL 15 с дефолтными настройками:
- *Добавляем в конфигурационный файл vagrant следующий скрипт:*
```ruby
config.vm.provision "shell", inline: <<-SHELL
    sudo apt-get update
    sudo apt-get install -y wget ca-certificates
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
    echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" |sudo tee  /etc/apt/sources.list.d/pgdg.list
    sudo apt-get update
    sudo apt-get install -y postgresql-15
SHELL
```
- *Применяем изменения:*
```bash
vagrant reload --provision
```

3. Создать БД для тестов: выполнить pgbench -i postgres:
- *Подключаемся к user postgres:*
```bash
sudo -i -u postgres psql
```
- *Создаём базу для тестов:*
```sql
CREATE DATABASE mytestdb;
```
- *Выполняем pgbench -i postgres:*
```bash
sudo -u postgres pgbench -i mytestdb
```
```bash
dropping old tables...
NOTICE:  table "pgbench_accounts" does not exist, skipping
NOTICE:  table "pgbench_branches" does not exist, skipping
NOTICE:  table "pgbench_history" does not exist, skipping
NOTICE:  table "pgbench_tellers" does not exist, skipping
creating tables...
generating data (client-side)...
100000 of 100000 tuples (100%) done (elapsed 0.05 s, remaining 0.00 s)
vacuuming...
creating primary keys...
done in 0.70 s (drop tables 0.01 s, create tables 0.00 s, client-side generate 0.19 s, vacuum 0.02 s, primary keys 0.48 s).
```

---

4. Запустить pgbench -c8 -P 6 -T 60 -U postgres postgres:
```bash
sudo -u postgres pgbench -c8 -P 6 -T 60 -U postgres mytestdb
```
```bash
pgbench (15.3 (Ubuntu 15.3-1.pgdg20.04+1))
starting vacuum...end.
progress: 6.0 s, 1070.5 tps, lat 7.433 ms stddev 12.774, 0 failed
progress: 12.0 s, 1053.7 tps, lat 7.584 ms stddev 11.397, 0 failed
progress: 18.0 s, 1118.3 tps, lat 7.144 ms stddev 12.750, 0 failed
progress: 24.0 s, 1066.1 tps, lat 7.491 ms stddev 14.195, 0 failed
progress: 30.0 s, 1093.2 tps, lat 7.301 ms stddev 13.465, 0 failed
progress: 36.0 s, 1063.1 tps, lat 7.517 ms stddev 11.377, 0 failed
progress: 42.0 s, 1076.5 tps, lat 7.419 ms stddev 12.402, 0 failed
progress: 48.0 s, 1091.2 tps, lat 7.319 ms stddev 10.718, 0 failed
progress: 54.0 s, 1014.4 tps, lat 7.872 ms stddev 15.280, 0 failed
progress: 60.0 s, 1048.6 tps, lat 7.617 ms stddev 8.948, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 8
number of threads: 1
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 64182
number of failed transactions: 0 (0.000%)
latency average = 7.466 ms
latency stddev = 12.443 ms
initial connection time = 12.395 ms
tps = 1069.590028 (without initial connection time)
```

---

5. Применить параметры настройки PostgreSQL из прикрепленного к материалам занятия файл:
```ruby
max_connections = 40
shared_buffers = 1GB
effective_cache_size = 3GB
maintenance_work_mem = 512MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 500
random_page_cost = 4
effective_io_concurrency = 2
work_mem = 6553kB
min_wal_size = 4GB
max_wal_size = 16GB
```
- *Перезапускаем postgresql:*
```bash
sudo service postgresql restart
```

---

6. Протестировать заново:
```bash
pgbench (15.3 (Ubuntu 15.3-1.pgdg20.04+1))
starting vacuum...end.
progress: 6.0 s, 871.3 tps, lat 9.143 ms stddev 23.358, 0 failed
progress: 12.0 s, 1061.1 tps, lat 7.524 ms stddev 4.614, 0 failed
progress: 18.0 s, 1087.7 tps, lat 7.338 ms stddev 4.961, 0 failed
progress: 24.0 s, 1107.0 tps, lat 7.218 ms stddev 5.032, 0 failed
progress: 30.0 s, 1160.0 tps, lat 6.885 ms stddev 3.741, 0 failed
progress: 36.0 s, 1056.8 tps, lat 7.555 ms stddev 4.374, 0 failed
progress: 42.0 s, 1134.7 tps, lat 7.038 ms stddev 4.390, 0 failed
progress: 48.0 s, 1048.3 tps, lat 7.618 ms stddev 4.607, 0 failed
progress: 54.0 s, 1125.3 tps, lat 7.095 ms stddev 4.402, 0 failed
progress: 60.0 s, 1099.1 tps, lat 7.267 ms stddev 4.754, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 8
number of threads: 1
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 64516
number of failed transactions: 0 (0.000%)
latency average = 7.427 ms
latency stddev = 7.973 ms
initial connection time = 12.431 ms
tps = 1075.199019 (without initial connection time)
```
*Наблюдаем следующие изменения:*  

    - Средняя задержка (latency average) немного снизилась: было 7.466 мс, стало 7.427 мс. Это означает, что в среднем транзакции обрабатывались немного быстрее.

    - Стандартное отклонение задержки (latency stddev) значительно снизилось: было 12.443 мс, стало 7.973 мс. Это указывает на то, что изменчивость времени обработки транзакций уменьшилась. То есть, система стала более предсказуемой в плане времени обработки транзакций.

    - Число транзакций в секунду (tps) немного увеличилось: было 1069.59, стало 1075.20. То есть, производительность системы немного увеличилась.

    - Общее количество обработанных транзакций немного увеличилось: было 64182, стало 64516.

---

7. Создать таблицу с текстовым полем и заполнить случайными или сгенерированными данным в размере 1млн строк:
```sql
CREATE TABLE my_table (info text);
INSERT INTO my_table (info)
SELECT md5(random()::text)
FROM generate_series(1, 1000000);
```

8. Посмотреть размер файла с таблицей:
```sql
SELECT pg_size_pretty(pg_total_relation_size('my_table'));
```
```bash
 pg_size_pretty
----------------
 65 MB
(1 row)
```

---

9. 5 раз обновить все строчки и добавить к каждой строчке любой символ:
```sql
DO $$ 
BEGIN 
  FOR i IN 1..5 LOOP 
    UPDATE my_table SET info = info || 'a'; 
  END LOOP; 
END; $$;
```

---

10. Посмотреть количество мертвых строчек в таблице и когда последний раз приходил автовакуум:
```sql
SELECT 
    relname, n_live_tup, n_dead_tup, 
    trunc(100*n_dead_tup/(n_live_tup+1))::float "ratio%", 
    last_autovacuum 
FROM pg_stat_user_TABLEs 
WHERE relname = 'my_table'
```
```bash
 relname  | n_live_tup | n_dead_tup | ratio% |        last_autovacuum
----------+------------+------------+--------+-------------------------------
 my_table |    1000000 |    5000000 |    499 | 2023-07-03 14:46:33.147473+00
(1 row)
```

---

11. 5 раз обновить все строчки и добавить к каждой строчке любой символ и посмотреть размер файла с таблицей:
```sql
DO $$ 
BEGIN 
  FOR i IN 1..5 LOOP 
    UPDATE my_table SET info = info || '*'; 
  END LOOP; 
END; $$;
```
- *Смотрим размер:*
```sql
SELECT pg_size_pretty(pg_total_relation_size('my_table'));

 pg_size_pretty
----------------
 415 MB
(1 row)
```
---

12. Отключить Автовакуум на конкретной таблице:
```sql
ALTER TABLE my_table SET (autovacuum_enabled = false, toast.autovacuum_enabled = false);
```
---

13. 10 раз обновить все строчки и добавить к каждой строчке любой символ и посмотреть размер файла с таблицей. Объясните полученный результат:
- *Обновляем строки:*
```sql
DO $$ 
BEGIN 
  FOR i IN 1..10 LOOP 
    UPDATE my_table SET info = info || 'a'; 
  END LOOP; 
END; $$;
```
- *Смотрим размер таблицы:*
```sql
SELECT pg_size_pretty(pg_total_relation_size('my_table'));

 pg_size_pretty
----------------
 841 MB
(1 row)
```
- *Рост размера таблицы обусловлен, тем что обыный VACUUM удаляет лишь мёртвые строки, но не освобождает физическое пространство на самом диске. Если мы хотим уменьшить размер самой таблицы, то необходимо выполнить VACUUM FULL. После отключенного Автовакуума мёртвые строки не удалились, соответственно это необходимо делать вручную. Даже если мы включим автовакуум обратно, то он запуститься лишь после внесения изменения в самой таблице*
- *Вкючаем Автовакуум обратно:*
```sql
ALTER TABLE my_table SET (autovacuum_enabled = true, toast.autovacuum_enabled = true);
```

14. Задание со *: Написать анонимную процедуру, в которой в цикле 10 раз обновятся все строчки в искомой таблице. Не забыть вывести номер шага цикла.
```sql
DO $$ 
DECLARE
  step integer;
BEGIN 
  FOR step IN 1..10 LOOP 
    RAISE NOTICE 'Step %', step;
    UPDATE my_table SET info = info || '-'; 
  END LOOP; 
END; $$;
```