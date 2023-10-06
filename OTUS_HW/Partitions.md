# **Секционирование таблицы**

## **Цель:**
### - научиться секционировать таблицы;

-----------------------------
**Секционировать большую таблицу из демо базы flights**
1. В качестве стенда для работы с PostgreSQL, использовал ВМ из проекта [Patroni](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/Project.md)
----------------------------
2. Базу можно скачать по нижеуказанной ссылке  
[Ссылка для скачивание](https://postgrespro.ru/docs/postgrespro/10/demodb-bookings-installation)

-------------------------------
3. Подключаемся к PostgreSQL и создадим базу
```bash
psql -h 192.168.10.14 -p 5000 -U postgres
```
```sql
CREATE DATABASE demo;
```
---------------------
4. Скачиваем базу на Ubuntu с PostgreSQL
```bash
wget https://edu.postgrespro.ru/demo-big.zip
```
-----------------
5. Импортируем данные в базу
```bash
psql -h 192.168.10.14 -p 5000 -U postgres -d demo < demo_big.sql
```
--------------
6. Продключаеся к базе и проверяем каталоги
```bash
psql -h 192.168.10.14 -p 5000 -U postgres -d demo
```
```bash
psql:\l

                                             List of databases
   Name    |  Owner   | Encoding | Collate |  Ctype  | ICU Locale | Locale Provider |   Access privileges
-----------+----------+----------+---------+---------+------------+-----------------+-----------------------
 airs      | postgres | UTF8     | C.UTF-8 | C.UTF-8 |            | libc            |
 company   | postgres | UTF8     | C.UTF-8 | C.UTF-8 |            | libc            |
 demo      | postgres | UTF8     | C.UTF-8 | C.UTF-8 |            | libc            |
 postgres  | postgres | UTF8     | C.UTF-8 | C.UTF-8 |            | libc            |
 template0 | postgres | UTF8     | C.UTF-8 | C.UTF-8 |            | libc            | =c/postgres          +
           |          |          |         |         |            |                 | postgres=CTc/postgres
 template1 | postgres | UTF8     | C.UTF-8 | C.UTF-8 |            | libc            | =c/postgres          +
           |          |          |         |         |            |                 | postgres=CTc/postgres
 testdb    | postgres | UTF8     | C.UTF-8 | C.UTF-8 |            | libc            |
(7 rows)
```
------------------
7. В качестве таблицы для партиционирования я выбрал таблицу Flights. Рассмотрим подход по по диапазону на scheduled_departure
  
Создаём главную таблицу:
```sql
CREATE TABLE flights_range (
   flight_id INT,	
   flight_no BPCHAR(6),	
   scheduled_departure TIMESTAMPTZ,	
   scheduled_arrival TIMESTAMPTZ,	
   departure_airport BPCHAR(3),	
   arrival_airport BPCHAR(3),	
   "status" VARCHAR(20),	
   aircraft_code BPCHAR(3),	
   actual_departure TIMESTAMPTZ,	
   actual_arrival TIMESTAMPTZ
) PARTITION BY RANGE (scheduled_departure);
```

Определяем диапазон дат:
```sql
SELECT MIN(scheduled_departure)::date, MAX(scheduled_departure)::date FROM flights;
```
```bash

    min     |    max
------------+------------
 2016-08-14 | 2017-09-14
(1 row)
```
Создаём функцию для автоматического создания партиций:
```sql
CREATE OR REPLACE FUNCTION create_partitions_for_existing_data()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    start_date DATE := ' 2016-08-01'; -- начальная дата
    end_date DATE := '2017-10-01'; -- дата после последнего месяца
    cur_date DATE := start_date;
    partition_name TEXT;
BEGIN
    WHILE cur_date < end_date LOOP
        partition_name := 'flights_range_' || to_char(cur_date, 'YYYY_MM');

        EXECUTE 'CREATE TABLE IF NOT EXISTS ' || partition_name || ' PARTITION OF flights_range
                 FOR VALUES FROM (''' || cur_date || ''') TO (''' || (cur_date + INTERVAL '1 MONTH')::DATE || ''')';

        -- Переместить данные из основной таблицы в партицию
        EXECUTE 'INSERT INTO ' || partition_name || ' SELECT * FROM flights_range WHERE 
                 scheduled_departure >= ''' || cur_date || ''' AND 
                 scheduled_departure < ''' || (cur_date + INTERVAL '1 MONTH')::DATE || '''';

        -- Увеличить текущую дату на месяц
        cur_date := cur_date + INTERVAL '1 MONTH';
    END LOOP;
END;
$$;
```

- Запускаем функцию create_partitions_for_existing_data:
```sql
SELECT create_partitions_for_existing_data();
```

- Заливаем данные из существующей таблицы
```sql
INSERT INTO flights_range
SELECT * FROM flights;
```

- Проверяем список партиций:
```sql
SELECT 
    parent.relname AS parent_table,
    child.relname AS partition_name,
    pg_partition_tree(child.oid) AS partition_tree,
    pg_total_relation_size(child.oid) AS partition_size
FROM 
    pg_inherits
JOIN 
    pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN 
    pg_class child ON pg_inherits.inhrelid = child.oid
WHERE 
    parent.relname = 'flights_range' -- имя родительской таблицы
ORDER BY 
    partition_name;
```
```bash
 parent_table  |    partition_name     |              partition_tree               | partition_size
---------------+-----------------------+-------------------------------------------+----------------
 flights_range | flights_range_2016_08 | (flights_range_2016_08,flights_range,t,0) |        1900544
 flights_range | flights_range_2016_09 | (flights_range_2016_09,flights_range,t,0) |        3317760
 flights_range | flights_range_2016_10 | (flights_range_2016_10,flights_range,t,0) |        3448832
 flights_range | flights_range_2016_11 | (flights_range_2016_11,flights_range,t,0) |        3334144
 flights_range | flights_range_2016_12 | (flights_range_2016_12,flights_range,t,0) |        3432448
 flights_range | flights_range_2017_01 | (flights_range_2017_01,flights_range,t,0) |        3440640
 flights_range | flights_range_2017_02 | (flights_range_2017_02,flights_range,t,0) |        3112960
 flights_range | flights_range_2017_03 | (flights_range_2017_03,flights_range,t,0) |        3432448
 flights_range | flights_range_2017_04 | (flights_range_2017_04,flights_range,t,0) |        3334144
 flights_range | flights_range_2017_05 | (flights_range_2017_05,flights_range,t,0) |        3440640
 flights_range | flights_range_2017_06 | (flights_range_2017_06,flights_range,t,0) |        3317760
 flights_range | flights_range_2017_07 | (flights_range_2017_07,flights_range,t,0) |        3448832
 flights_range | flights_range_2017_08 | (flights_range_2017_08,flights_range,t,0) |        3284992
 flights_range | flights_range_2017_09 | (flights_range_2017_09,flights_range,t,0) |        1449984
(14 rows)

```
- Первое с чем я столунулся - с проблемой приведения типа данных ::date
```sql
EXPLAIN SELECT * FROM flights WHERE scheduled_departure::date = '2016-12-11';
```
```sql
                                 QUERY PLAN
----------------------------------------------------------------------------
 Gather  (cost=1000.00..5627.29 rows=1074 width=63)
   Workers Planned: 1
   ->  Parallel Seq Scan on flights  (cost=0.00..4519.89 rows=632 width=63)
         Filter: ((scheduled_departure)::date = '2016-12-11'::date)
(4 rows)
```
```sql
EXPLAIN SELECT * FROM flights WHERE scheduled_departure::date = '2016-12-11';
```
```sql
                                                  QUERY PLAN
---------------------------------------------------------------------------------------------------------------
 Gather  (cost=1000.00..10289.04 rows=2148 width=63)
   Workers Planned: 2
   ->  Parallel Append  (cost=0.00..9074.24 rows=893 width=63)
         ->  Parallel Seq Scan on flights_range_2016_10 flights_range_3  (cost=0.00..714.42 rows=99 width=63)
               Filter: ((scheduled_departure)::date = '2016-12-11'::date)
         ->  Parallel Seq Scan on flights_range_2017_07 flights_range_12  (cost=0.00..714.42 rows=99 width=63)
               Filter: ((scheduled_departure)::date = '2016-12-11'::date)
         ->  Parallel Seq Scan on flights_range_2017_01 flights_range_6  (cost=0.00..713.02 rows=99 width=63)
               Filter: ((scheduled_departure)::date = '2016-12-11'::date)
         ->  Parallel Seq Scan on flights_range_2017_05 flights_range_10  (cost=0.00..712.84 rows=99 width=63)
               Filter: ((scheduled_departure)::date = '2016-12-11'::date)
         ->  Parallel Seq Scan on flights_range_2016_12 flights_range_5  (cost=0.00..711.54 rows=99 width=63)
               Filter: ((scheduled_departure)::date = '2016-12-11'::date)
         ->  Parallel Seq Scan on flights_range_2017_03 flights_range_8  (cost=0.00..711.15 rows=99 width=63)
               Filter: ((scheduled_departure)::date = '2016-12-11'::date)
         ->  Parallel Seq Scan on flights_range_2017_08 flights_range_13  (cost=0.00..694.09 rows=99 width=63)
               Filter: ((scheduled_departure)::date = '2016-12-11'::date)
         ->  Parallel Seq Scan on flights_range_2017_04 flights_range_9  (cost=0.00..690.96 rows=96 width=63)
               Filter: ((scheduled_departure)::date = '2016-12-11'::date)
         ->  Parallel Seq Scan on flights_range_2016_11 flights_range_4  (cost=0.00..690.38 rows=96 width=63)
               Filter: ((scheduled_departure)::date = '2016-12-11'::date)
         ->  Parallel Seq Scan on flights_range_2016_09 flights_range_2  (cost=0.00..687.50 rows=95 width=63)
               Filter: ((scheduled_departure)::date = '2016-12-11'::date)
         ->  Parallel Seq Scan on flights_range_2017_06 flights_range_11  (cost=0.00..687.50 rows=95 width=63)
               Filter: ((scheduled_departure)::date = '2016-12-11'::date)
         ->  Parallel Seq Scan on flights_range_2017_02 flights_range_7  (cost=0.00..644.09 rows=89 width=63)
               Filter: ((scheduled_departure)::date = '2016-12-11'::date)
         ->  Parallel Seq Scan on flights_range_2016_08 flights_range_1  (cost=0.00..390.81 rows=54 width=63)
               Filter: ((scheduled_departure)::date = '2016-12-11'::date)
         ->  Parallel Seq Scan on flights_range_2017_09 flights_range_14  (cost=0.00..307.03 rows=45 width=65)
               Filter: ((scheduled_departure)::date = '2016-12-11'::date)
```
*можно увидеть, что запрос к партиционированной таблице обходится дороже, т.к. scheduled_departure::date препятствует оптимизатору PostgreSQL корректно пропускать ненужные партиции*  
  
- Немного исправим наш запрос:
```sql
EXPLAIN SELECT * FROM flights
WHERE scheduled_departure BETWEEN '2016-12-11 00:00:00' AND '2016-12-11 23:59:59';
```
```bash
-[ RECORD 1 ]---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
QUERY PLAN | Index Scan using flights_flight_no_scheduled_departure_key on flights  (cost=0.42..3603.76 rows=539 width=63)
-[ RECORD 2 ]---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
QUERY PLAN |   Index Cond: ((scheduled_departure >= '2016-12-11 00:00:00+00'::timestamp with time zone) AND (scheduled_departure <= '2016-12-11 23:59:59+00'::timestamp with time zone))
```

```sql
EXPLAIN SELECT * FROM flights_range 
WHERE scheduled_departure BETWEEN '2016-12-11 00:00:00' AND '2016-12-11 23:59:59';
```
```bash
-[ RECORD 1 ]-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
QUERY PLAN | Seq Scan on flights_range_2016_12 flights_range  (cost=0.00..919.12 rows=1045 width=63)
-[ RECORD 2 ]-----------------------------------------------------------------------------------------------------------------------------------------------------------------------
QUERY PLAN |   Filter: ((scheduled_departure >= '2016-12-11 00:00:00+00'::timestamp with time zone) AND (scheduled_departure <= '2016-12-11 23:59:59+00'::timestamp with time zone))
```
*Здесь можно увидеть, что в первом случае идёт поиск по индексу, во втором - последовательное сканирование в нужной партиции. Чтобы улучшить производительность можно создать индекс*

- Создадим индекс для партиционированной таблицы:
```sql
CREATE INDEX idx_flights_range_scheduled_departure ON flights_range (scheduled_departure);
```
- Проверяем планировщик:
```sql
EXPLAIN SELECT * FROM flights_range 
WHERE scheduled_departure BETWEEN '2016-12-11 00:00:00' AND '2016-12-11 23:59:59';
```
```bash
-[ RECORD 1 ]---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
QUERY PLAN | Bitmap Heap Scan on flights_range_2016_12 flights_range  (cost=13.20..443.88 rows=1045 width=63)
-[ RECORD 2 ]---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
QUERY PLAN |   Recheck Cond: ((scheduled_departure >= '2016-12-11 00:00:00+00'::timestamp with time zone) AND (scheduled_departure <= '2016-12-11 23:59:59+00'::timestamp with time zone))
-[ RECORD 3 ]---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
QUERY PLAN |   ->  Bitmap Index Scan on flights_range_2016_12_scheduled_departure_idx  (cost=0.00..12.94 rows=1045 width=0)
-[ RECORD 4 ]---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
QUERY PLAN |         Index Cond: ((scheduled_departure >= '2016-12-11 00:00:00+00'::timestamp with time zone) AND (scheduled_departure <= '2016-12-11 23:59:59+00'::timestamp with time zone))
```
*Здесь можно отметить, что создание индекса значительно улучшило производительность запроса*

--------------------------

8. Теперь рассмотрим вариант партиционирования по скписку на departure_airport;  

- Сначала создаём главную таблицу:
```sql
CREATE TABLE flights_list (
    -- перечисляем все поля таблицы Flights, например:
    flight_id INT,	
    flight_no BPCHAR(6),	
    scheduled_departure TIMESTAMPTZ,	
    scheduled_arrival TIMESTAMPTZ,	
    departure_airport BPCHAR(3),	
    arrival_airport BPCHAR(3),	
    "status" VARCHAR(20),	
    aircraft_code BPCHAR(3),	
    actual_departure TIMESTAMPTZ,	
    actual_arrival TIMESTAMPTZ
) PARTITION BY LIST (departure_airport);
```

- Создаём партиции
```bash
DO $$
DECLARE
    airport_code_value text;
BEGIN
    FOR airport_code_value IN (SELECT DISTINCT departure_airport FROM flights)
    LOOP
        EXECUTE format('CREATE TABLE IF NOT EXISTS flights_list_%s PARTITION OF flights_list FOR VALUES IN (%L)',
                       airport_code_value, airport_code_value);
    END LOOP;
END;
$$ LANGUAGE plpgsql;
```

- Заливаем данные из существующей таблицы
```sql
INSERT INTO flights_list
SELECT * FROM flights;
```
- Проверяем список партиций:
```sql
SELECT 
    parent.relname AS parent_table,
    child.relname AS partition_name,
    pg_partition_tree(child.oid) AS partition_tree,
    pg_total_relation_size(child.oid) AS partition_size
FROM 
    pg_inherits
JOIN 
    pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN 
    pg_class child ON pg_inherits.inhrelid = child.oid
WHERE 
    parent.relname = 'flights_list' -- имя родительской таблицы
ORDER BY 
    partition_name;
```
```bash
 parent_table |  partition_name  |           partition_tree            | partition_size
--------------+------------------+-------------------------------------+----------------
 flights_list | flights_list_aaq | (flights_list_aaq,flights_list,t,0) |         114688
 flights_list | flights_list_aba | (flights_list_aba,flights_list,t,0) |         188416
 flights_list | flights_list_aer | (flights_list_aer,flights_list,t,0) |         417792
 flights_list | flights_list_arh | (flights_list_arh,flights_list,t,0) |         245760
 flights_list | flights_list_asf | (flights_list_asf,flights_list,t,0) |         122880
 flights_list | flights_list_bax | (flights_list_bax,flights_list,t,0) |         139264
 flights_list | flights_list_bqs | (flights_list_bqs,flights_list,t,0) |          65536
 flights_list | flights_list_btk | (flights_list_btk,flights_list,t,0) |          65536
 flights_list | flights_list_bzk | (flights_list_bzk,flights_list,t,0) |         434176

...
(104 rows)
```
-----------------------------

9. Так же можно рассмотреть партиционирование по хешу  

- Сначала создаём главную таблицу:
```sql
CREATE TABLE flights_hash (
    -- перечисляем все поля таблицы Flights, например:
    flight_id INT,	
    flight_no BPCHAR(6),	
    scheduled_departure TIMESTAMPTZ,	
    scheduled_arrival TIMESTAMPTZ,	
    departure_airport BPCHAR(3),	
    arrival_airport BPCHAR(3),	
    "status" VARCHAR(20),	
    aircraft_code BPCHAR(3),	
    actual_departure TIMESTAMPTZ,	
    actual_arrival TIMESTAMPTZ
) PARTITION BY HASH (flight_id);
```
- Создаём партиции
```bash
CREATE TABLE flights_hash_part1 PARTITION OF Flights_hash
FOR VALUES WITH (MODULUS 4, REMAINDER 0);

CREATE TABLE flights_hash_part2 PARTITION OF Flights_hash
FOR VALUES WITH (MODULUS 4, REMAINDER 1);

CREATE TABLE flights_hash_part3 PARTITION OF Flights_hash
FOR VALUES WITH (MODULUS 4, REMAINDER 2);

CREATE TABLE flights_hash_part4 PARTITION OF Flights_hash
FOR VALUES WITH (MODULUS 4, REMAINDER 3);
```
- Заливаем данные из существующей таблицы
```sql
INSERT INTO flights_hash
SELECT * FROM flights;
```
- Проверяем
```sql
SELECT 
    parent.relname AS parent_table,
    child.relname AS partition_name,
    pg_partition_tree(child.oid) AS partition_tree,
    pg_total_relation_size(child.oid) AS partition_size
FROM 
    pg_inherits
JOIN 
    pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN 
    pg_class child ON pg_inherits.inhrelid = child.oid
WHERE 
    parent.relname = 'flights_hash' -- имя родительской таблицы
ORDER BY 
    partition_name;
```
```bash
 parent_table |   partition_name   |            partition_tree             | partition_size
--------------+--------------------+---------------------------------------+----------------
 flights_hash | flights_hash_part1 | (flights_hash_part1,flights_hash,t,0) |        5398528
 flights_hash | flights_hash_part2 | (flights_hash_part2,flights_hash,t,0) |        5439488
 flights_hash | flights_hash_part3 | (flights_hash_part3,flights_hash,t,0) |        5390336
 flights_hash | flights_hash_part4 | (flights_hash_part4,flights_hash,t,0) |        5423104
(4 rows)
```