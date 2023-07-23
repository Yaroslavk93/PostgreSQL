# **Бэкапы**

## **Цель:**
### - Применить логический бэкап.
### - Восстановиться из бэкапа.

------------------

1. Создаем ВМ/докер c ПГ.
*Машину разворачивал на Vagrant. Конфиг ВМ с установкой Postgres 15*
```ruby
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
``````
-------------------------

2. Создаем БД, схему и в ней таблицу.
*Подключаемся к postgres*
```bash
sudo -i -u postgres psql
``````
*Создаём базу*
```sql
CREATE DATABASE mytestdb;
```
*Подключаемся к созданной базе*
```sql
\c mytestdb
``````
*Создаем схему и таблицу*
```sql
CREATE SCHEMA test_schema;
CREATE TABLE test_schema.test_table (id serial primary key, name varchar(50), email varchar(50));
``````

--------------------------

3. Заполним таблицы автосгенерированными 100 записями.
```sql
INSERT INTO test_schema.test_table (name, email)
SELECT md5(random()::text), md5(random()::text)
FROM generate_series(1, 100);
``````
```sql
SELECT * FROM test_schema.test_table LIMIT 10;

 id |               name               |              email
----+----------------------------------+----------------------------------
  1 | ae68de7283cccf550c98911d1d0dd554 | e41f531a39806ebfb404c075d792ca35
  2 | acaeae491b080952343d8fd15402c9c0 | c139606d653ec3e06364e198e730236c
  3 | 46b873d7e5389aece8cc335578d34b16 | 6ea78941fa7525e9a1c2cf1e02460dc0
  4 | e15c411eec603c756f183151f436816d | af4253b8cc8ce47e0c667e8dabf56044
  5 | 85f909342e2c9b6008cc42103a4a6839 | a3b6a2e37885b58a7eef252f9d3d1a6a
  6 | 029b276d93b226ef117a8e621f267a23 | c32967583d8a6e5a1f5270aca222d835
  7 | 014c9e2434114c5965a9adefa1f64ae0 | 546ea4aba0bc2d0e4511dd627282bd65
  8 | 92ebe74d8ca3b961e488c0f4cb375030 | 430eb42df5358c90ffa95ad938111ce7
  9 | 2aff382a3294a03347c6b236928a1bd0 | 1f02aec4fce18196d8d83ba4626d9089
 10 | 552a5002f4db6a92d822a13ce178224f | 6523b818dbcacb36e2601512e0d8eb94
(10 rows)
``````

-------------------------

4. Под линукс пользователем Postgres создадим каталог для бэкапов.
*Подключаемся к пользователю postgres*
```bash
sudo su - postgres
```
*Создаём директорию для бэкапов в домашнем коталоге*
```bash
mkdir ~/backups
``````
*Проверяем права доступа*
```bash
ls -l ~/

total 71420
drwxr-xr-x 3 postgres postgres     4096 Jul  3 14:16  15
drwxrwxr-x 2 postgres postgres     4096 Jul 23 16:45  backups
-rw-rw-r-- 1 postgres postgres 73114624 Jul  9 20:13  db.out
``````

---------------------

5. Сделаем логический бэкап используя утилиту COPY.
```bash
psql -U postgres -d mytestdb -c "\copy (SELECT * FROM test_schema.test_table) TO '~/backups/test_table.csv' WITH CSV"

COPY 100
``````
*Проверим содержимое созданного файла*
```dotnetcli
cat ~/backups/test_table.csv

1,ae68de7283cccf550c98911d1d0dd554,e41f531a39806ebfb404c075d792ca35
2,acaeae491b080952343d8fd15402c9c0,c139606d653ec3e06364e198e730236c
3,46b873d7e5389aece8cc335578d34b16,6ea78941fa7525e9a1c2cf1e02460dc0
4,e15c411eec603c756f183151f436816d,af4253b8cc8ce47e0c667e8dabf56044
5,85f909342e2c9b6008cc42103a4a6839,a3b6a2e37885b58a7eef252f9d3d1a6a
...
``````

---------------

6. Восстановим во вторую таблицу данные из бэкапа.
*Создадим новую таблицу с теми же параметрами, что и в 1ой*
```bash
psql -U postgres -d mytestdb -c "CREATE TABLE test_schema.test_table2 (id serial primary key, name varchar(50), email varchar(50));"
```
*Восстановим в нее данные из бэкапа*
```sql
\copy test_schema.test_table2 FROM '~/backups/test_table.csv' CSV
```
*Проверим содержимое*
```sql
SELECT * FROM test_schema.test_table2 LIMIT 10;

 id |               name               |              email
----+----------------------------------+----------------------------------
  1 | ae68de7283cccf550c98911d1d0dd554 | e41f531a39806ebfb404c075d792ca35
  2 | acaeae491b080952343d8fd15402c9c0 | c139606d653ec3e06364e198e730236c
  3 | 46b873d7e5389aece8cc335578d34b16 | 6ea78941fa7525e9a1c2cf1e02460dc0
  4 | e15c411eec603c756f183151f436816d | af4253b8cc8ce47e0c667e8dabf56044
  5 | 85f909342e2c9b6008cc42103a4a6839 | a3b6a2e37885b58a7eef252f9d3d1a6a
  6 | 029b276d93b226ef117a8e621f267a23 | c32967583d8a6e5a1f5270aca222d835
  7 | 014c9e2434114c5965a9adefa1f64ae0 | 546ea4aba0bc2d0e4511dd627282bd65
  8 | 92ebe74d8ca3b961e488c0f4cb375030 | 430eb42df5358c90ffa95ad938111ce7
  9 | 2aff382a3294a03347c6b236928a1bd0 | 1f02aec4fce18196d8d83ba4626d9089
 10 | 552a5002f4db6a92d822a13ce178224f | 6523b818dbcacb36e2601512e0d8eb94
(10 rows)
``````

---------------

7. Используя утилиту pg_dump создадим бэкап в кастомном сжатом формате двух таблиц
```bash
pg_dump -U postgres -F c -b -v -f ~/backups/testdb.backup -t test_schema.test_table -t test_schema.test_table2 mytestdb

pg_dump: last built-in OID is 16383
pg_dump: reading extensions
pg_dump: identifying extension members
pg_dump: reading schemas
pg_dump: reading user-defined tables
pg_dump: reading user-defined functions
pg_dump: reading user-defined types
pg_dump: reading procedural languages
pg_dump: reading user-defined aggregate functions
pg_dump: reading user-defined operators
pg_dump: reading user-defined access methods
pg_dump: reading user-defined operator classes
pg_dump: reading user-defined operator families
pg_dump: reading user-defined text search parsers
pg_dump: reading user-defined text search templates
pg_dump: reading user-defined text search dictionaries
pg_dump: reading user-defined text search configurations
pg_dump: reading user-defined foreign-data wrappers
pg_dump: reading user-defined foreign servers
pg_dump: reading default privileges
pg_dump: reading user-defined collations
pg_dump: reading user-defined conversions
pg_dump: reading type casts
pg_dump: reading transforms
pg_dump: reading table inheritance information
pg_dump: reading event triggers
pg_dump: finding extension tables
pg_dump: finding inheritance relationships
pg_dump: reading column info for interesting tables
pg_dump: finding table default expressions
pg_dump: flagging inherited columns in subtables
pg_dump: reading partitioning data
pg_dump: reading indexes
pg_dump: flagging indexes in partitioned tables
pg_dump: reading extended statistics
pg_dump: reading constraints
pg_dump: reading triggers
pg_dump: reading rewrite rules
pg_dump: reading policies
pg_dump: reading row-level security policies
pg_dump: reading publications
pg_dump: reading publication membership of tables
pg_dump: reading publication membership of schemas
pg_dump: reading subscriptions
pg_dump: reading large objects
pg_dump: reading dependency data
pg_dump: saving encoding = UTF8
pg_dump: saving standard_conforming_strings = on
pg_dump: saving search_path =
pg_dump: saving database definition
pg_dump: dumping contents of table "test_schema.test_table"
pg_dump: dumping contents of table "test_schema.test_table2"
``````

-U postgres: Здесь -U указывает на имя пользователя, которое следует использовать для подключения к базе данных. В этом случае это "postgres".  
  
-F c: Здесь -F указывает на формат выходного файла. c означает "custom", то есть пользовательский формат, который является бинарным и сжатым по умолчанию.  
  
-b: Этот флаг говорит о том, что следует включить в бэкап большие объекты (BLOBs).  
  
-v: Этот флаг указывает на то, что pg_dump должен работать в режиме подробного вывода ("verbose mode"), выводя дополнительную информацию во время выполнения.  
  
-f "~/backups/testdb.backup": Здесь -f указывает на имя файла, в который будет сохранен бэкап. В данном случае это "testdb.backup" в директории "backups" домашнего каталога текущего пользователя.  
  
-t test_schema.test_table -t test_schema.test_table2: Эти опции -t указывают на конкретные таблицы, которые нужно включить в бэкап. В данном случае это таблицы "test_table" и "test_table2" из схемы "test_schema".  
  
testdb: Это последний аргумент, он указывает на имя базы данных, из которой создается бэкап.
  
  
*Сравним размер сжатого файла с оригиналами таблиц*
```bash
ls -lh ~/backups/testdb.backup

-rw-rw-r-- 1 postgres postgres 13K Jul 23 17:11 /var/lib/postgresql/backups/testdb.backup
```
```sql
SELECT 
    pg_size_pretty(pg_total_relation_size('test_schema.test_table')) AS test_table_size,
    pg_size_pretty(pg_total_relation_size('test_schema.test_table2')) AS test_table2_size;

 test_table_size | test_table2_size
-----------------+------------------
 56 kB           | 56 kB
(1 row)
``````

--------------------------

8. Используя утилиту pg_restore восстановим в новую БД только вторую таблицу!
*Создадим новую базу*
```bash
createdb -U postgres testdb2
``````
*Восстановим только вторую таблицу*
```bash
pg_restore -U postgres -d testdb2 -t test_schema.test_table2 -v ~/backups/testdb.backup

pg_restore: implied data-only restore
``````
*Данная ошибка (pg_restore: implied data-only restore) говорит о том, что структура таблицы test_table2 не существует в целевой базе данных testdb2*
  
*Создадим схему в базе testdb2*
```bash
psql -U postgres -d testdb2 -c "CREATE SCHEMA test_schema;"
``````
*Далее я пошёл путём создания списка объектов для восстановления*
```bash
pg_restore -l ~/backups/testdb.backup > restore.list
``````
```bash
nano restore.list

228; 1259 25220 TABLE test_schema test_table2 postgres
227; 1259 25219 SEQUENCE test_schema test_table2_id_seq postgres
3334; 0 0 SEQUENCE OWNED BY test_schema test_table2_id_seq postgres
3175; 2604 25223 DEFAULT test_schema test_table2 id postgres
3327; 0 25220 TABLE DATA test_schema test_table2 postgres
3336; 0 0 SEQUENCE SET test_schema test_table2_id_seq postgres
3179; 2606 25225 CONSTRAINT test_schema test_table2 test_table2_pkey postgres
``````
*Восстанавливаем данные из второй таблицы*
```bash
pg_restore -U postgres -d testdb2 -L restore.list ~/backups/testdb.backup
``````
*Проверяем*
```bash
psql -U postgres -d testdb2 -c "SELECT * FROM test_schema.test_table2 LIMIT 10;"

 id |               name               |              email
----+----------------------------------+----------------------------------
  1 | ae68de7283cccf550c98911d1d0dd554 | e41f531a39806ebfb404c075d792ca35
  2 | acaeae491b080952343d8fd15402c9c0 | c139606d653ec3e06364e198e730236c
  3 | 46b873d7e5389aece8cc335578d34b16 | 6ea78941fa7525e9a1c2cf1e02460dc0
  4 | e15c411eec603c756f183151f436816d | af4253b8cc8ce47e0c667e8dabf56044
  5 | 85f909342e2c9b6008cc42103a4a6839 | a3b6a2e37885b58a7eef252f9d3d1a6a
  6 | 029b276d93b226ef117a8e621f267a23 | c32967583d8a6e5a1f5270aca222d835
  7 | 014c9e2434114c5965a9adefa1f64ae0 | 546ea4aba0bc2d0e4511dd627282bd65
  8 | 92ebe74d8ca3b961e488c0f4cb375030 | 430eb42df5358c90ffa95ad938111ce7
  9 | 2aff382a3294a03347c6b236928a1bd0 | 1f02aec4fce18196d8d83ba4626d9089
 10 | 552a5002f4db6a92d822a13ce178224f | 6523b818dbcacb36e2601512e0d8eb94
(10 rows)
``````