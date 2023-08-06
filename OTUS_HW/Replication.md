# **Репликация**

## **Цель:**
### - Реализовать свой миникластер на 3 ВМ.

------------------------

- Для начала мы создаём 3 + 1(*) Виртуальные машины с одинаковыми параметрами
```ruby
Vagrant.configure("2") do |config|

  config.vm.provider "virtualbox" do |v|
    v.memory = 4096  # ОЗУ
    v.cpus = 2  # ядра
  end

  # Конфигурация диска
  config.vm.disk :disk, size: "5GB", primary: true


  # Метод создания виртуальной машины
  def create_vm(config, name, ip, host_port)
    config.vm.define name do |vm|
      vm.vm.box = "ubuntu/focal64"
      vm.vm.network "private_network", ip: ip
      vm.vm.network "forwarded_port", guest: 5432, host: host_port, id: "postgres_#{name}"

      # Скрипт для установки PostgreSQL
      vm.vm.provision "shell", inline: <<-SHELL
        sudo apt-get update
        sudo apt-get install -y wget ca-certificates
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
        echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" |sudo tee  /etc/apt/sources.list.d/pgdg.list
        sudo apt-get update
        sudo apt-get install -y postgresql-15
      SHELL
    end
  end


    # Создание виртуальных машин
    create_vm(config, "vm1", "192.168.50.3", 5433)
    create_vm(config, "vm2", "192.168.50.4", 5434)
    create_vm(config, "vm3", "192.168.50.5", 5435)
    create_vm(config, "vm4", "192.168.50.6", 5436)

end
```

--------------------

1. На 1 ВМ создаем таблицы test для записи, test2 для запросов на чтение. 
*Подключаемся к базе с учётной записи postgres и задаём пароль*
```bash
sudo -i -u postgres psql
``` 
```sql
ALTER USER postgres PASSWORD '*****';
```
*Создаём базу и подключаемся к ней*
```sql
CREATE DATABASE testdb;
\c testdb
```
*Создаём схему*
```sql
CREATE SCHEMA test_schema;
```
*Создаём таблицы*
```sql
CREATE TABLE test_schema.test (id serial primary key, data text);
CREATE TABLE test_schema.test2 (id serial primary key, data text);
```
*Далее создаём роли на запись и на чтение*
```sql
CREATE USER role_write PASSWORD '*****';
CREATE USER role_read PASSWORD '*****';

-- Даём права на запись для таблицы `test`
REVOKE ALL ON TABLE test_schema.test FROM PUBLIC;
GRANT USAGE ON SCHEMA test_schema TO role_write;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE test_schema.test TO role_write;

-- Даём права только на чтение для таблицы `test2`
REVOKE ALL ON TABLE test_schema.test2 FROM PUBLIC;
GRANT USAGE ON SCHEMA test_schema TO role_read;
GRANT SELECT ON TABLE test_schema.test2 TO role_read;
```

---------------------

2. Создаем публикацию таблицы test и подписываемся на публикацию таблицы test2 с ВМ №2.
*Для начала мы меняем следующие конфигурационные параметры*
```sql
ALTER SYSTEM SET wal_level = logical;
ALTER SYSTEM SET max_replication_slots = 5;
ALTER SYSTEM SET max_wal_senders = 5;
ALTER SYSTEM SET listen_addresses = '*'; 
```
*Применяем изменения*
```sql
SELECT pg_reload_conf();
```
*Настраиваем подключение*
```bash
sudo nano /etc/postgresql/15/main/pg_hba.conf

host    all             all             0.0.0.0/0              scram-sha-256
host    replication     all             0.0.0.0/0              scram-sha-256
```
*Рестартуем postgresql*
```bash
systemctl restart postgresql
```
*Создаём публикацию таблицы test*
```sql
CREATE PUBLICATION test_pub FOR TABLE test_schema.test;
```
*Подписываемся на публикацию с VM1 от **VM2** (Данный пункт сделал после создания таблиц на **VM2**)*
```sql
CREATE SUBSCRIPTION test_sub CONNECTION 'host=192.168.50.3 port=5432 dbname=testdb user=postgres password=*****' PUBLICATION test_pub;
```

-----------------------

3. На 2 ВМ создаем таблицы test2 для записи, test для запросов на чтение.
*Делаем аналогично с VM1*
```sql
ALTER USER postgres PASSWORD '*****';

CREATE DATABASE testdb;
\c testdb

CREATE SCHEMA test_schema;

CREATE TABLE test_schema.test (id serial primary key, data text);
CREATE TABLE test_schema.test2 (id serial primary key, data text);

CREATE USER role_write PASSWORD '*****';
CREATE USER role_read PASSWORD '*****';

-- Даём права на запись для таблицы `test2`
REVOKE ALL ON TABLE test_schema.test2 FROM PUBLIC;
GRANT USAGE ON SCHEMA test_schema TO role_write;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE test_schema.test2 TO role_write;

-- Даём права только на чтение для таблицы `test`
REVOKE ALL ON TABLE test_schema.test FROM PUBLIC;
GRANT USAGE ON SCHEMA test_schema TO role_read;
GRANT SELECT ON TABLE test_schema.test TO role_read;
```

-------------

4. Создаем публикацию таблицы test2 и подписываемся на публикацию таблицы test1 с ВМ №1.
*Аналогично VM1*
```sql
ALTER SYSTEM SET wal_level = logical;
ALTER SYSTEM SET max_replication_slots = 5;
ALTER SYSTEM SET max_wal_senders = 5;
ALTER SYSTEM SET listen_addresses = '*'; 

SELECT pg_reload_conf();
```
```bash
sudo nano /etc/postgresql/15/main/pg_hba.conf

host    all             all             0.0.0.0/0              scram-sha-256
host    replication     all             0.0.0.0/0              scram-sha-256
```
```bash
systemctl restart postgresql
```
*Создаём публикацию*
```sql
CREATE PUBLICATION test2_pub FOR TABLE test_schema.test2;
```
*Подписываемся на публикацию с VM1*
```sql
CREATE SUBSCRIPTION test2_sub CONNECTION 'host=192.168.50.4 port=5432 dbname=testdb user=postgres password=*****' PUBLICATION test2_pub;
```

-----------------

5. 3 ВМ использовать как реплику для чтения и бэкапов (подписаться на таблицы из ВМ №1 и №2 ).
*Настраиваем для выполнения горячего реплицирования в следующем пункте*
```sql
ALTER SYSTEM SET wal_level = replica;
ALTER SYSTEM SET archive_mode = on;
ALTER SYSTEM SET archive_command = 'cp %p /var/lib/postgresql/15/main/archive/%f';
ALTER SYSTEM SET listen_addresses = '*'; 
ALTER SYSTEM SET max_wal_senders = 3;
ALTER SYSTEM SET wal_keep_size = 1024;
ALTER SYSTEM SET hot_standby = on;

SELECT pg_reload_conf();
```
```bash
sudo nano /etc/postgresql/15/main/pg_hba.conf

host    all             all             0.0.0.0/0              scram-sha-256
host    replication     all             0.0.0.0/0              scram-sha-256
```
```bash
systemctl restart postgresql
```
*Подписываемся на таблицы из VM1 и VM2*
```sql
CREATE SUBSCRIPTION test_sub2 CONNECTION 'host=192.168.50.3 port=5432 dbname=testdb user=postgres password=*****' PUBLICATION test_pub;

CREATE SUBSCRIPTION test2_sub2 CONNECTION 'host=192.168.50.4 port=5432 dbname=testdb user=postgres password=*****' PUBLICATION test2_pub;
```
*Получил ошибку*
```sql
ERROR:  schema "test_schema" does not exist
```
*Создаём базу и необходимые схемы*
```sql
ALTER USER postgres PASSWORD '*****';

CREATE DATABASE testdb;
\c testdb

CREATE SCHEMA test_schema;

CREATE TABLE test_schema.test (id serial primary key, data text);
CREATE TABLE test_schema.test2 (id serial primary key, data text);
```
*Повторяем подписку*
```sql
CREATE SUBSCRIPTION test_sub2 CONNECTION 'host=192.168.50.3 port=5432 dbname=testdb user=postgres password=*****' PUBLICATION test_pub;

CREATE SUBSCRIPTION test2_sub2 CONNECTION 'host=192.168.50.4 port=5432 dbname=testdb user=postgres password=*****' PUBLICATION test2_pub;
```

-------------------

6. Реализовать горячее реплицирование для высокой доступности на 4ВМ. Источником должна выступать ВМ №3. Написать с какими проблемами столкнулись.    
*Создадим роль для репликации на ВМ3*
```sql
CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD '*****';
```
*Останавливаем PostgreSQL на ВМ4*
```bash
systemctl stop postgresql
```
*На ВМ4 выполним базовый бэкап с ВМ3, чтобы в базе на ВМ4 уже были ранее созданные данные*
```bash
mkdir /var/lib/postgresql/15/backup

pg_basebackup -h 192.168.50.5 -D /var/lib/postgresql/15/backup -U replicator -P --wal-method=fetch
```
*Удааляем текущие данные на ВМ4 и перемещаем резервную копию в каталог данных*
```bash
rm -rf /var/lib/postgresql/15/main/* 

mv /var/lib/postgresql/15/backup/* /var/lib/postgresql/15/main/

chown -R postgres:postgres /var/lib/postgresql/15/main
```
*Обновляем конфигурационные параметры*
```bash
sudo -u postgres echo "primary_conninfo = 'host=192.168.50.5 port=5432 user=replicator  password=admin'" >> /etc/postgresql/15/main/postgresql.conf

sudo -u postgres echo "promote_trigger_file = '/tmp/trigger_file'" >> /etc/postgresql/15/main/postgresql.conf
```
*Настройку режима реплики указываем в файле standby.signal в каталоге данных*
```bash
sudo touch /var/lib/postgresql/15/main/standby.signal
```
*Запускаем ВМ*
```bash
systemctl start postgresql
```

---------------

6. Далее проведём тесты, и убедимся, что всё настроили правильно.  
*Проверим логическую репликацию на ВМ1 и ВМ2*
```sql
SELECT * FROM pg_publication;

-[ RECORD 1 ]+---------
oid          | 16410
pubname      | test_pub
pubowner     | 10
puballtables | f
pubinsert    | t
pubupdate    | t
pubdelete    | t
pubtruncate  | t
pubviaroot   | f


SELECT * FROM pg_subscription;

-[ RECORD 1 ]----+-----------------------------------------------------------------------
oid              | 16412
subdbid          | 16388
subskiplsn       | 0/0
subname          | test2_sub
subowner         | 10
subenabled       | t
subbinary        | f
substream        | f
subtwophasestate | d
subdisableonerr  | f
subconninfo      | host=192.168.50.4 port=5432 dbname=testdb user=postgres password=*****
subslotname      | test2_sub
subsynccommit    | off
subpublications  | {test2_pub}
```
*На ВМ3 проверим подписки и горячее реплицирование*
```sql
SELECT * FROM pg_subscription;

-[ RECORD 1 ]---------+------------------------------
subid                 | 16409
subname               | test_sub2
pid                   | 24459
relid                 |
received_lsn          | 0/19905B0
last_msg_send_time    | 2023-08-06 15:38:53.852563+00
last_msg_receipt_time | 2023-08-06 15:39:19.94387+00
latest_end_lsn        | 0/19905B0
latest_end_time       | 2023-08-06 15:38:53.852563+00
-[ RECORD 2 ]---------+------------------------------
subid                 | 16410
subname               | test2_sub2
pid                   | 24461
relid                 |
received_lsn          | 0/198D3A8
last_msg_send_time    | 2023-08-06 15:38:43.136358+00
last_msg_receipt_time | 2023-08-06 15:39:06.958365+00
latest_end_lsn        | 0/198D3A8
latest_end_time       | 2023-08-06 15:38:43.136358+00


SELECT * FROM pg_stat_replication;

-[ RECORD 1 ]----+------------------------------
pid              | 24974
usesysid         | 16411
usename          | replicator
application_name | 15/main
client_addr      | 192.168.50.6
client_hostname  |
client_port      | 58916
backend_start    | 2023-08-06 15:32:52.629623+00
backend_xmin     |
state            | streaming
sent_lsn         | 0/4000148
write_lsn        | 0/4000148
flush_lsn        | 0/4000148
replay_lsn       | 0/4000148
write_lag        |
flush_lag        |
replay_lag       |
sync_priority    | 0
sync_state       | async
reply_time       | 2023-08-06 15:46:31.627019+00
```
*Подключаемся к ВМ1 и вносим запись*
```bash
psql -U role_write -h localhost -d testdb
```
```sql
INSERT INTO test_schema.test (id, data) VALUES (1, 'Test data for table test');
```
*Для проверки прав доступа, используем следующие команды*
```sql
SELECT * FROM information_schema.role_table_grants WHERE table_name = 'test';
SELECT * FROM information_schema.role_table_grants WHERE table_name = 'test2';
```
*На ВМ2 подключаемся к роли на чтение и проверяем запись*
```bash
psql -U role_read -h localhost -d testdb
```
```sql
SELECT * FROM test_schema.test;

 id |           data
----+--------------------------
  1 | Test data for table test
(1 row)
```
*Делаем аналогичный запрос с ВМ3 и ВМ4*
```sql
SELECT * FROM test_schema.test;

 id |           data
----+--------------------------
  1 | Test data for table test
(1 row)
```
*При настройке реплицирования возникали лишь простые проблемы, связанные с конфигурационными параметрами. Кластер реализован*