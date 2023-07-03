# **Работа с базами данных, пользователями и правами**

## **Цель:**
### - создание новой базы данных, схемы и таблицы;
### - создание роли для чтения данных из созданной схемы созданной базы данных;
### - создание роли для чтения и записи из созданной схемы созданной базы данных.

-------------------

1. Запуск Виртуальной машины:
```bash
vagrant up
``` 

-----------

2. Зайдите в созданный кластер под пользователем postgres:
```bash
sudo -i -u postgres psql
```

-------------

3. Создайте новую базу данных testdb:
```sql
CREATE DATABASE testdb;
```

-----------------------

4. Зайдите в созданную базу данных под пользователем postgres:
```sql
\c testdb
```
```bash
You are now connected to database "testdb" as user "postgres".
```

-------------------------

5. Создайте новую схему testnm:
```sql
CREATE SCHEMA testnm;
```

----------------------

6. Создайте новую таблицу t1 с одной колонкой c1 типа integer:
```sql
CREATE TABLE testnm.t1 (c1 integer);
```

------------------

7. Вставьте строку со значением c1=1:
```sql
INSERT INTO testnm.t1 VALUES (1);
```

-----------------

8. Создайте новую роль readonly:
```sql
CREATE ROLE readonly;
```

--------------

9. Дайте новой роли право на подключение к базе данных testdb:
```sql
GRANT CONNECT ON DATABASE testdb TO readonly;
```

----------------------------

10. Дайте новой роли право на использование схемы testnm:
```sql
GRANT USAGE ON SCHEMA testnm TO readonly;
```

----------------

11. Дайте новой роли право на select для всех таблиц схемы testnm:
```sql
GRANT SELECT ON ALL TABLES IN SCHEMA testnm TO readonly;
```

12. Создайте пользователя testread с паролем test123:
```sql
CREATE USER testread WITH PASSWORD 'test123';
```

--------------

13. Дайте роль readonly пользователю testread:
```sql
GRANT readonly TO testread;
```

-----

14. Зайдите под пользователем testread в базу данных testdb:
```sql
\c testdb testread
```
- *Получил следующую ошибку*
```bash
FATAL:  Peer authentication failed for user "testread"
Previous connection kept
```
- *Решил следующим образом - менял параметры в pg_hba.config (peer заменил на md5)*

```bash
You are now connected to database "testdb" as user "testread".
```

-------

15. Сделайте select * from t1:
```sql
SELECT * FROM testnm.t1;
```
- *Вывод:*  
 c1  
\----  
  1  
(1 row)

---------------

16. Посмотрите на список таблиц:
```sql
\dt
```
- **Вывод:**
```bash
Did not find any relations.
```
- **А почему так получилось с таблицей**
*Это связано с тем, что сама таблица находится с схеме public, к которой нет доступа у данного пользователя*

--------------------------

17. Вернитесь в базу данных testdb под пользователем postgres:
```sql
\c testdb postgres
```

-----------------

18. Удалите таблицу t1:
```sql
DROP TABLE testnm.t1;
```

--------------------

19. Создайте ее заново но уже с явным указанием имени схемы testnm:
```sql
CREATE TABLE testnm.t1 (c1 integer);
```

---------

20. вставьте строку со значением c1=1:
```sql
INSERT INTO testnm.t1 VALUES (1);
```

-------------

21. Зайдите под пользователем testread в базу данных testdb:
```sql
\c testdb testread
```
```bash
You are now connected to database "testdb" as user "testread".
```

--------

22. Сделайте select * from testnm.t1;
```sql
SELECT * FROM testnm.t1;
```
```bash
2023-07-03 10:03:09.282 UTC [29926] testread@testdb ERROR:  permission denied for table t1
2023-07-03 10:03:09.282 UTC [29926] testread@testdb STATEMENT:  SELECT * FROM testnm.t1;
ERROR:  permission denied for table t1
```
*Ошибка связана с тем, что не выданы права на соответствующую схему и таблицу. Чтобы данная ситуация не повторилась, необходимо настроить привилегии на автоматическую выдачу прав SELECT для новых таблиц*
- *Подключаемся к учётке postgres:*
```sql
\c testdb postgres;
```
- *Выдаём необходимые привилегии для новых таблиц:*
```sql
ALTER default privileges in SCHEMA testnm grant SELECT on TABLES to readonly; 
```
- *Выдаём права на чтение уже существующих таблиц в схеме:*
```sql
GRANT SELECT ON ALL TABLES IN SCHEMA testnm TO readonly;
```
- *Подключаемся к testread и проверяем:*  
 c1  
\----  
  1  
(1 row)

--------------------

23. Теперь попробуйте выполнить команду create table t2(c1 integer); insert into t2 values (2);
```sql
CREATE TABLE t2(c1 integer); INSERT INTO t2 VALUES (2);
```
```bash
CREATE TABLE
INSERT 0 1
```
*Запрос выполнился, т.к. объект создался в схеме public, и чтобы этого не произошло необходимо убрать права на создание объектов в схеме public*
```sql
REVOKE CREATE on SCHEMA public FROM public; 
REVOKE ALL on DATABASE testdb FROM public; 
```
*Так же можно задать путь к базе по умолчанию*
```sql
ALTER USER testread SET search_path TO testnm;
```

------------

24. Теперь попробуйте выполнить команду create table t3(c1 integer); insert into t2 values (2);
```sql
CREATE TABLE t3 (c1 integer); 
INSERT INTO t2 VALUES (2);
```

- *Вывод ошибки:*
```bash
2023-07-03 10:34:02.577 UTC [30863] testread@testdb ERROR:  permission denied for schema public at character 14
2023-07-03 10:34:02.577 UTC [30863] testread@testdb STATEMENT:  CREATE TABLE t3 (c1 integer);
ERROR:  permission denied for schema public
LINE 1: CREATE TABLE t3 (c1 integer);
```

*Таблица не создалась, тк мы отозвали права на создание объектов в схеме public*