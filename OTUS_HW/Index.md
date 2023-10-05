# **Работа с индексами, join'ами, статистикой**

## **Цель:**
### - знать и уметь применять основные виды индексов PostgreSQL;
### - строить и анализировать план выполнения запроса;
### - уметь оптимизировать запросы для с использованием индексов;
### - знать и уметь применять различные виды join'ов;
### - строить и анализировать план выполенения запроса;
### - оптимизировать запрос;
### - уметь собирать и анализировать статистику для таблицы;

-----------------------------------------

## Вариант 1

1. **Создать индекс к какой-либо из таблиц вашей БД:**

- *В качестве стенда для работы с PostgreSQL, использовал ВМ из проекта [Patroni](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/Project.md)*

- *Подключаемся к базе:*
```bash
psql -h 192.168.10.14 -p 5000 -U postgres
```
- *Создаём базу и таблицу для теста:*
```sql
CREATE DATABASE company;
\c company

CREATE SCHEMA department;
CREATE TABLE department.employees(
    id SERIAL PRIMARY KEY,
    first_name TEXT,
    last_name TEXT,
    position TEXT,
    description TEXT,
    status TEXT
);
```
- *В качестве данных, использвал генерациют от библиотеки Faker. Создадим виртуальное окружение и активируем (делал на своём локальном хосте Windows 11):*
```bash
cd data/catalog
python -m venv env

env\Scripts\activate.bat
```
- *Ставим библиотеки. Обратите внимание на параметры устрановки библиотеки psycopg2. На Вашей системе должен стоять PostgreSQL, либо используйте пакет psycopg2-binary. Версия интерпритатора python тоже имеет значение - в моём случае python 3.11*  
```bash
pip install faker
pip install psycopg2
```
- *Выбираем нужный интерпритатор и генерим данные:*
```python
from faker import Faker
import psycopg2

fake = Faker()

# Устанавливаем соединение с PostgreSQL
conn = psycopg2.connect(
    dbname="company",
    user="postgres",
    password="admin",
    host="192.168.10.14",
    port="5000"
)

cur = conn.cursor()

for _ in range(10000):
    first_name = fake.first_name()
    last_name = fake.last_name()
    position = fake.job()
    description = fake.text()
    status = "active" if fake.boolean(chance_of_getting_true=70) else "inactive"

    cur.execute(
        "INSERT INTO employees (first_name, last_name, position, description, status) VALUES (%s, %s, %s, %s, %s)",
        (first_name, last_name, position, description, status)
    )

conn.commit()
cur.close()
conn.close()
```
- *Проверяем сгенерированные данные:*
```sql
SELECT * FROM department.employees;
```
```bash
-[ RECORD 1 ]---------------------------------------------------------------------------------------------------------------
--------------------------------------------------
id          | 1
first_name  | Tyler
last_name   | Brooks
position    | Engineer, control and instrumentation
description | Real century before involve push. Have lawyer paper difference two new.
                                                  +
            | Yard better space beat. West market arm though to.
                                                  +
            | Space property task discussion. Cultural feeling argue offer.
status      | active
-[ RECORD 2 ]---------------------------------------------------------------------------------------------------------------
--------------------------------------------------
id          | 2
first_name  | Jesus
last_name   | Bailey
position    | Photographer
description | South fish what wait really room car. Air very all. Maintain almost majority herself.
                                                  +
            | Use every especially try indeed relationship. Society strong against perhaps.
status      | active
-[ RECORD 3 ]---------------------------------------------------------------------------------------------------------------
--------------------------------------------------
id          | 3
first_name  | Rebecca
last_name   | Evans
position    | Diplomatic Services operational officer
description | High together most as. Ground live decade writer could.
                                                  +
            | Economy management political land Mr trial. Understand individual project small.
status      | inactive

...
```
- *Проверяем план запроса перед созданием индекса:*
```sql
EXPLAIN SELECT * FROM department.employees WHERE position = 'Photographer';
```
```bash
                          QUERY PLAN
--------------------------------------------------------------
 Seq Scan on employees  (cost=0.00..412.25 rows=15 width=195)
   Filter: ("position" = 'Photographer'::text)
(2 rows)
```
- *Создадим базовый индекс для столбца 'position':*
```sql
CREATE INDEX idx_position ON department.employees (position);
```
------------------------------------------------------

2. **Прислать текстом результат команды explain, в которой используется данный индекс:**
```sql
EXPLAIN SELECT * FROM department.employees WHERE position = 'Photographer';
```
```bash
                                 QUERY PLAN
----------------------------------------------------------------------------
 Bitmap Heap Scan on employees  (cost=1.50..17.85 rows=15 width=195)
   Recheck Cond: ("position" = 'Photographer'::text)
   ->  Bitmap Index Scan on idx_position  (cost=0.00..1.50 rows=15 width=0)
         Index Cond: ("position" = 'Photographer'::text)
(4 rows)
```
*Было: Последовательное сканирование (Seq Scan).*  
- *До создания индекса PostgreSQL использовал Seq Scan, что означает, что он последовательно просматривал каждую строку в таблице employees, чтобы определить, соответствует ли она условию фильтрации (position = 'Photographer').* 
  
*Стало: Сканирование кучи с помощью битовой карты (Bitmap Heap Scan) с использованием индексного сканирования (Bitmap Index Scan)*  
- *Bitmap Index Scan: При этом этапе PostgreSQL использует созданный индекс idx_position для быстрого определения расположения строк, соответствующих условию (position = 'Photographer'). Этот этап генерирует "битовую карту" (bitmap), где каждый бит представляет блок данных в таблице и указывает, содержит ли этот блок интересующие нас строки.*

- *Bitmap Heap Scan: Затем PostgreSQL просматривает фактические блоки данных, используя битовую карту, созданную на предыдущем этапе, чтобы извлечь соответствующие строки. "Recheck Cond" указывает, что PostgreSQL может повторно проверить условие для строк, которые он извлекает, чтобы убедиться, что они действительно соответствуют критериям.*
  
*Создание индекса значительно улучшило производительность запроса, потому что PostgreSQL теперь может быстро определить, какие блоки данных содержат интересующие нас строки, без необходимости просматривать каждую строку в таблице. Однако стоит помнить, что индексы также имеют свою стоимость в виде дополнительного места на диске и небольшого замедления при выполнении операций вставки, обновления или удаления, поскольку индекс также должен быть обновлен.*

-----------------------------------------------------
3. **Реализовать индекс для полнотекстового поиска:**
- *Делаем Explain до добавления индекса:*
```sql
EXPLAIN SELECT * FROM department.employees WHERE to_tsvector('english', description) @@ to_tsquery('english', 'land');
```
```bash
                                    QUERY PLAN
-----------------------------------------------------------------------------------
 Seq Scan on employees  (cost=0.00..2937.25 rows=50 width=195)
   Filter: (to_tsvector('english'::regconfig, description) @@ '''land'''::tsquery)
(2 rows)
```
- *Добавляем индекс для полнотекстового поиска c использованием to_tsvector:*
```sql
CREATE INDEX idx_textsearch ON department.employees USING gin(to_tsvector('english', description));
```
- *Проверяем и сравниваем план запроса:*
```sql
EXPLAIN SELECT * FROM department.employees WHERE to_tsvector('english', description) @@ to_tsquery('english', 'land');
```
```bash
                                         QUERY PLAN
---------------------------------------------------------------------------------------------
 Bitmap Heap Scan on employees  (cost=3.69..65.57 rows=50 width=195)
   Recheck Cond: (to_tsvector('english'::regconfig, description) @@ '''land'''::tsquery)
   ->  Bitmap Index Scan on idx_textsearch  (cost=0.00..3.68 rows=50 width=0)
         Index Cond: (to_tsvector('english'::regconfig, description) @@ '''land'''::tsquery)
(4 rows)
```
*После добавления индекса PostgreSQL больше не использует Seq Scan. Вместо этого он выполняет Bitmap Index Scan на индексе idx_textsearch. Это означает, что система использует созданный индекс для быстрого нахождения соответствующих строк без необходимости проверять каждую строку в таблице. Это гораздо быстрее, особенно на больших таблицах.*  
  
*Вывод:*  
*Добавление индекса idx_textsearch существенно улучшило производительность запроса. Вместо того чтобы проверять каждую строку в таблице, PostgreSQL теперь может использовать индекс для быстрого определения релевантных строк. Это демонстрирует преимущества использования индексов, особенно для операций, которые могут быть оптимизированы с их помощью, таких как полнотекстовый поиск.*

----------------
4. **Реализовать индекс на часть таблицы или индекс на поле с функцией:**
- *Смоотрим план до создаяния индекса на часть таблицы:*
```sql
EXPLAIN SELECT * FROM department.employees WHERE id = 6 AND status = 'active';
```
```bash
                                    QUERY PLAN
----------------------------------------------------------------------------------
 Index Scan using employees_pkey on employees  (cost=0.29..2.51 rows=1 width=195)
   Index Cond: (id = 6)
   Filter: (status = 'active'::text)
(3 rows)
```
- *Создаём индекс на часть таблицы:*
```sql
CREATE INDEX idx_active_employees ON department.employees (id) WHERE status = 'active';
```
- *Проверяем план и сравниваем результат:*
```sql
EXPLAIN SELECT * FROM department.employees WHERE id = 6 AND status = 'active';
```
```bash
                                       QUERY PLAN
----------------------------------------------------------------------------------------
 Index Scan using idx_active_employees on employees  (cost=0.28..2.50 rows=1 width=195)
   Index Cond: (id = 6)
(2 rows)
```
*Тип операции: Index Scan — также сканирование индекса, но теперь используется специальный индекс idx_active_employees, который содержит только строки со статусом active.*  
  
*Стоимость (cost): 0.28..2.50. Стоимость немного уменьшилась по сравнению с предыдущим запросом.*  
  
*Условие индекса: Index Cond: (id = 6). PostgreSQL использует индекс idx_active_employees для быстрого поиска строки по id.*  
  
*Вывод:*  
*Добавление индекса на часть таблицы (только на строки со статусом active) позволило немного уменьшить стоимость запроса. На практике, особенно при больших объемах данных, такой индекс может сделать запросы быстрее, так как они будут работать только с активными строками и игнорировать остальные. В данном конкретном случае разница не слишком велика, но она может стать заметной при больших объемах данных или более сложных запросах.*
  
  
  
- *Смортим план до создания индекса с функцией:*
```sql
EXPLAIN SELECT * FROM department.employees WHERE LENGTH(first_name) = 5;
```
```bash
                          QUERY PLAN
--------------------------------------------------------------
 Seq Scan on employees  (cost=0.00..437.50 rows=50 width=195)
   Filter: (length(first_name) = 5)
(2 rows)
```
- *Создаём индекс с функцией:*
```sql
CREATE INDEX idx_name_length ON department.employees (LENGTH(first_name));
```
- *Проверяем план и сравниваем результат:*
```sql
EXPLAIN SELECT * FROM department.employees WHERE LENGTH(first_name) = 5;
```
```bash
                                  QUERY PLAN
-------------------------------------------------------------------------------
 Bitmap Heap Scan on employees  (cost=1.77..51.28 rows=50 width=195)
   Recheck Cond: (length(first_name) = 5)
   ->  Bitmap Index Scan on idx_name_length  (cost=0.00..1.76 rows=50 width=0)
         Index Cond: (length(first_name) = 5)
(4 rows)
```
*Тип операции: Bitmap Heap Scan — PostgreSQL использует bitmap, чтобы определить, какие строки следует извлечь из таблицы.*  
  
*Стоимость (cost): 1.77..51.28. Стоимость запроса уменьшилась по сравнению с первоначальным запросом.*  
  
*Повторная проверка: Recheck Cond: (length(first_name) = 5). PostgreSQL делает повторную проверку строк после извлечения их на основе bitmap.*  
  
*Тип вложенной операции: Bitmap Index Scan — PostgreSQL использует созданный индекс idx_name_length для определения строк, которые следует извлечь.*  
  
*Условие индекса: Index Cond: (length(first_name) = 5). Запрос использует индекс, чтобы быстро находить строки с именем заданной длины.*
  
*Вывод:*  
*Добавление индекса на функцию (в данном случае на length(first_name)) позволило заметно улучшить производительность запроса. Вместо того чтобы последовательно просматривать каждую строку таблицы, PostgreSQL может теперь использовать индекс для быстрого определения тех строк, которые соответствуют условию. Это особенно полезно на больших объемах данных, где разница в производительности будет более заметной.*
----------------
5. **Создать индекс на несколько полей:**
- *Для наглядности - найдём пользователей, у которых совпадения и по имени и по фамилии:*
```sql
SELECT 
    e1.id AS user1_id, 
    e1.first_name AS user1_first_name, 
    e1.last_name AS user1_last_name,
    e2.id AS user2_id, 
    e2.first_name AS user2_first_name, 
    e2.last_name AS user2_last_name
FROM 
    department.employees e1
JOIN 
    department.employees e2 ON e1.first_name = e2.first_name AND e1.last_name = e2.last_name
WHERE 
    e1.id < e2.id;
```
```bash
 user1_id | user1_first_name | user1_last_name | user2_id | user2_first_name | user2_last_name
----------+------------------+-----------------+----------+------------------+-----------------
     3698 | Adam             | Baker           |     7887 | Adam             | Baker
     1424 | Adam             | Johnson         |     2528 | Adam             | Johnson
      242 | Adam             | Williams        |     6166 | Adam             | Williams
     4089 | Alan             | Johnson         |     4597 | Alan             | Johnson
     6015 | Alex             | Smith           |     7061 | Alex             | Smith
     3732 | Alex             | Smith           |     6015 | Alex             | Smith
     3732 | Alex             | Smith           |     7061 | Alex             | Smith
     5231 | Alexandra        | Smith           |     8727 | Alexandra        | Smith
     2662 | Alexis           | Clark           |     6899 | Alexis           | Clark
     2049 | Alexis           | Moore           |     7590 | Alexis           | Moore
     1414 | Amanda           | Johnson         |     7965 | Amanda           | Johnson
     4088 | Amanda           | Jones           |     4527 | Amanda           | Jones
     4897 | Amanda           | Kelley          |     9513 | Amanda           | Kelley
     6157 | Amanda           | Miller          |     8677 | Amanda           | Miller
     1171 | Amanda           | Smith           |     2116 | Amanda           | Smith
      499 | Amanda           | Stafford        |     5591 | Amanda           | Stafford
     3926 | Amanda           | Thomas          |     5413 | Amanda           | Thomas
      577 | Amy              | Craig           |     1886 | Amy              | Craig
     4277 | Amy              | Johnson         |     8784 | Amy              | Johnson
     4277 | Amy              | Johnson         |     8094 | Amy              | Johnson
     8094 | Amy              | Johnson         |     8784 | Amy              | Johnson
...
```
- *Смотрим план до добавления индекса:*
```sql
EXPLAIN SELECT * FROM department.employees WHERE first_name = 'Amy' AND last_name = 'Johnson';
```
```bash
                                QUERY PLAN
--------------------------------------------------------------------------
 Seq Scan on employees  (cost=0.00..437.50 rows=1 width=195)
   Filter: ((first_name = 'Amy'::text) AND (last_name = 'Johnson'::text))
(2 rows)
```
- *Создадим индекс на несколько полей:*
```sql
CREATE INDEX idx_full_name ON department.employees (first_name, last_name);
```
- *смотрим планировщик и сравниваем:*
```sql
EXPLAIN SELECT * FROM department.employees WHERE first_name = 'Amy' AND last_name = 'Johnson';
```
```bash
                                   QUERY PLAN
---------------------------------------------------------------------------------
 Index Scan using idx_full_name on employees  (cost=0.29..2.50 rows=1 width=195)
   Index Cond: ((first_name = 'Amy'::text) AND (last_name = 'Johnson'::text))
(2 rows)
```
*Тип операции: Index Scan — сканирование индекса. Вместо того чтобы проверять каждую строку таблицы, PostgreSQL может использовать индекс для быстрого нахождения строк, удовлетворяющих условиям запроса.*  
  
*Стоимость (cost): 0.29..2.50. Стоимость гораздо ниже, чем у Seq Scan, потому что индекс позволяет быстро найти нужные строки, минуя большую часть таблицы.*  
  
*Условие индекса: Index Cond: ((first_name = 'Amy'::text) AND (last_name = 'Johnson'::text)). Это условие показывает, какие критерии используются для поиска в индексе.*  
  
*Вывод:*  
*Добавление индекса на поля first_name и last_name значительно улучшило производительность запроса. Стоимость выполнения запроса существенно уменьшилась благодаря использованию индекса, что позволяет быстро находить нужные строки без необходимости просматривать всю таблицу.*

---------------------------------

6. **Написать комментарии к каждому из индексов:**

```sql
COMMENT ON INDEX department.idx_position IS 'Optimizes searches by position.';
COMMENT ON INDEX department.idx_textsearch IS 'Full-text search index for the description column.';
COMMENT ON INDEX department.idx_active_employees IS 'Index for quickly filtering active employees.';
COMMENT ON INDEX department.idx_name_length IS 'Index based on the length of the first name.';
COMMENT ON INDEX department.idx_full_name IS 'Optimizes searches by full name.';
```
- *Проверяем комменты:*
```sql
SELECT
    n.nspname AS schema_name,
    c.relname AS table_name,
    d.description AS comment
FROM
    pg_description d
JOIN pg_class c ON c.oid = d.objoid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE
    c.relkind = 'i' 
ORDER BY
    n.nspname,
    c.relname;
```
```bash
 schema_name |      table_name      |                      comment
-------------+----------------------+----------------------------------------------------
 department  | idx_active_employees | Index for quickly filtering active employees.
 department  | idx_full_name        | Optimizes searches by full name.
 department  | idx_name_length      | Index based on the length of the first name.
 department  | idx_position         | Optimizes searches by position.
 department  | idx_textsearch       | Full-text search index for the description column.
(5 rows)
```
-------------

7. **Выводы:**
- *Производительность при вставке: Когда вы добавляете много индексов, операции вставки, обновления и удаления могут стать медленнее, потому что каждый индекс требует обновления. Решение: Оцените необходимость каждого индекса и удалите те, которые редко используются.*  
  
- *Оверхед хранения: Индексы занимают место на диске. Если у вас много индексов, это может значительно увеличить объем занимаемого места. Решение: Регулярно анализируйте и оптимизируйте свои индексы, удаляя те, которые не приносят много пользы.*

-------------------

## Вариант 2

1. **Реализовать прямое соединение двух или более таблиц:**
- *Данную работу делал в ранее созданной тестовой СУБД testdb:*
```sql
-- Соединяем таблицу сотрудников с таблицей должностей по полю position_id
SELECT e.first_name, e.last_name, p.position_name
FROM employees e
JOIN positions p ON e.position_id = p.id;
``` 
*С помощью прямого соединения мы извлекаем имена сотрудников и их должности.*
---------------
2. **Реализовать левостороннее (или правостороннее) соединение двух или более таблиц:**
```sql
-- Выводим всех сотрудников и их проекты. Если у сотрудника нет проекта, он все равно будет в результатах.
SELECT e.first_name, e.last_name, pr.project_name
FROM employees e
LEFT JOIN projects pr ON e.id = pr.employee_id;
```
*Используем LEFT JOIN, чтобы показать всех сотрудников, даже тех, у кого нет связанных проектов.*
---------------
3. **Реализовать кросс соединение двух или более таблиц:**
```sql
-- Каждому сотруднику назначим каждую должность.
SELECT e.first_name, p.position_name
FROM employees e
CROSS JOIN positions p;
```
*Кросс соединение создает комбинации каждой строки первой таблицы с каждой строкой второй таблицы.*
---------------
4. **Реализовать полное соединение двух или более таблиц:**
```sql
-- Получаем список всех сотрудников и всех проектов. Если у сотрудника нет проекта или проект не связан с сотрудником, они все равно появятся в результатах.
SELECT e.first_name, e.last_name, pr.project_name
FROM employees e
FULL JOIN projects pr ON e.id = pr.employee_id;
```
---------------
5. **Реализовать запрос, в котором будут использованы разные типы соединений:**
```sql
-- Комбинированный запрос
SELECT e.first_name, e.last_name, p.position_name, pr.project_name
FROM employees e
JOIN positions p ON e.position_id = p.id
LEFT JOIN projects pr ON e.id = pr.employee_id;
```
*Этот запрос соединяет таблицы сотрудников и должностей с помощью прямого соединения, а затем присоединяет результат к таблице проектов с помощью левостороннего соединения.*
-------------
6. *Структура таблиц:*
```sql
-- Таблица сотрудников
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    first_name TEXT,
    last_name TEXT,
    position_id INT
);

-- Таблица должностей
CREATE TABLE positions (
    id SERIAL PRIMARY KEY,
    position_name TEXT
);

-- Таблица проектов
CREATE TABLE projects (
    id SERIAL PRIMARY KEY,
    project_name TEXT,
    employee_id INT
);
```
------------
### Задание со звёздочкой*

- *Придумайте 3 своих метрики на основе показанных представлений*  
  
1. *Среднее количество проектов на сотрудника:*
```sql
SELECT AVG(project_count)
FROM (
    SELECT e.id, COUNT(pr.id) as project_count
    FROM employees e
    LEFT JOIN projects pr ON e.id = pr.employee_id
    GROUP BY e.id
) as subquery;
```
2. *Количество сотрудников на каждую должность:*
```sql
SELECT p.position_name, COUNT(e.id) as employee_count
FROM positions p
LEFT JOIN employees e ON p.id = e.position_id
GROUP BY p.position_name;
```
3. *Должности без сотрудников:*
```sql
SELECT p.position_name
FROM positions p
LEFT JOIN employees e ON p.id = e.position_id
WHERE e.id IS NULL;
```
*Эти метрики могут быть полезными для анализа распределения рабочей нагрузки, определения наиболее востребованных должностей или выявления должностей, которые в настоящее время не заняты.*