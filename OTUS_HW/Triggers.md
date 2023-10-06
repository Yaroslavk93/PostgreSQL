# **Триггеры, поддержка заполнения витрин**

## **Цель:**
### - Создать триггер для поддержки витрины в актуальном состоянии;

------------------------------
1. В качестве стенда для работы с PostgreSQL, использовал ВМ из проекта [Patroni](https://github.com/Yaroslavk93/PostgreSQL/blob/main/Project_Patroni_Postgres/Project.md)

--------------------

2. Подготавливаем базу перед созданием триггера
  
- Создаём схему:
```sql
CREATE SCHEMA pract_functions;
SET search_path TO pract_functions,public;
```


- Создаём таблицу с товарами:
```sql
CREATE TABLE goods
(
    goods_id    integer PRIMARY KEY,
    good_name   varchar(63) NOT NULL,
    good_price  numeric(12, 2) NOT NULL CHECK (good_price > 0.0)
);

INSERT INTO goods (goods_id, good_name, good_price)
VALUES 	(1, 'Спички хозайственные', .50),
		(2, 'Автомобиль Ferrari FXX K', 185000000.01);
```

- Создаём таблицу с продажами:
```sql
CREATE TABLE sales
(
    sales_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    good_id     integer REFERENCES goods (goods_id),
    sales_time  timestamp with time zone DEFAULT now(),
    sales_qty   integer CHECK (sales_qty > 0)
);

INSERT INTO sales (good_id, sales_qty) VALUES (1, 10), (1, 1), (1, 120), (2, 1);
```
- Пример отчёта:
```sql
SELECT G.good_name, sum(G.good_price * S.sales_qty)
FROM goods G
INNER JOIN sales S ON S.good_id = G.goods_id
GROUP BY G.good_name;
```
- С увеличением объёма данных отчет стал создаваться медленно. Принято решение денормализовать БД, создать таблицу:
```sql
CREATE TABLE good_sum_mart
(
	good_name   varchar(63) NOT NULL,
	sum_sale	numeric(16, 2)NOT NULL
);
```
**Задача:**   
Создать триггер на таблице продаж, для поддержки данных в витрине в актуальном состоянии (вычисляющий при каждой продаже сумму и записывающий её в витрину)  
  
- Создание функции триггера:
```sql
CREATE OR REPLACE FUNCTION update_good_sum_mart()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        INSERT INTO good_sum_mart(good_name, sum_sale)
        VALUES (
            (SELECT good_name FROM goods WHERE goods_id = NEW.good_id),
            NEW.sales_qty * (SELECT good_price FROM goods WHERE goods_id = NEW.good_id)
        )
        ON CONFLICT(good_name) 
        DO UPDATE SET sum_sale = good_sum_mart.sum_sale + NEW.sales_qty * (SELECT good_price FROM goods WHERE goods_id = NEW.good_id);

        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        UPDATE good_sum_mart 
        SET sum_sale = sum_sale - OLD.sales_qty * (SELECT good_price FROM goods WHERE goods_id = OLD.good_id)
                       + NEW.sales_qty * (SELECT good_price FROM goods WHERE goods_id = NEW.good_id)
        WHERE good_name = (SELECT good_name FROM goods WHERE goods_id = NEW.good_id);

        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        UPDATE good_sum_mart 
        SET sum_sale = sum_sale - OLD.sales_qty * (SELECT good_price FROM goods WHERE goods_id = OLD.good_id)
        WHERE good_name = (SELECT good_name FROM goods WHERE goods_id = OLD.good_id);

        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;
```
- Создание триггера:
```sql
CREATE TRIGGER trg_sales_changes
AFTER INSERT OR UPDATE OR DELETE ON sales
FOR EACH ROW 
EXECUTE FUNCTION update_good_sum_mart();
```

- Проверим работу триггера - зальём данные:
```sql
INSERT INTO sales (good_id, sales_qty) VALUES (1, 5), (2, 2);
```
- Получил ошибку:
```sql
SQL Error [42P10]: ERROR: there is no unique or exclusion constraint matching the ON CONFLICT specification
  Где: SQL statement "INSERT INTO good_sum_mart(good_name, sum_sale)

        VALUES (

            (SELECT good_name FROM goods WHERE goods_id = NEW.good_id),

            NEW.sales_qty * (SELECT good_price FROM goods WHERE goods_id = NEW.good_id)

        )

        ON CONFLICT(good_name) 

        DO UPDATE SET sum_sale = good_sum_mart.sum_sale + NEW.sales_qty * (SELECT good_price FROM goods WHERE goods_id = NEW.good_id)"
PL/pgSQL function update_good_sum_mart() line 4 at SQL statement
```

- для решения данной проблемы, добавим уникальное ограничение (или первичный ключ) для поля good_name в таблице good_sum_mart
```sql
ALTER TABLE good_sum_mart
ADD CONSTRAINT unique_good_name UNIQUE(good_name);
```

- Проверим текущее состояние таблицы good_sum_mart:
```sql
SELECT * FROM good_sum_mart;

        good_name         |   sum_sale
--------------------------+--------------
 Спички хозайственные     |         5.00
 Автомобиль Ferrari FXX K | 740000000.04
```

```sql
UPDATE sales SET sales_qty = 20 WHERE sales_id = 1;
SELECT * FROM good_sum_mart;
```
```bash
        good_name         |   sum_sale
--------------------------+--------------
 Автомобиль Ferrari FXX K | 740000000.04
 Спички хозайственные     |        10.00
(2 rows)
```
```sql
DELETE FROM sales WHERE sales_id = 1;
SELECT * FROM good_sum_mart;
```
```sql
demo=# SELECT * FROM good_sum_mart;
        good_name         |   sum_sale
--------------------------+--------------
 Автомобиль Ferrari FXX K | 740000000.04
 Спички хозайственные     |         9.50
```
------------------------------

**Задание со звездочкой*:**  
  
Чем такая схема (витрина+триггер) предпочтительнее отчета, создаваемого "по требованию" (кроме производительности)?

1. Актуальность данных: Витрина обновляется в реальном времени, что позволяет получать актуальную информацию без необходимости ждать формирования отчета.  
2. Стабильность нагрузки: Так как данные агрегируются заранее, нагрузка на сервер становится более предсказуемой и равномерной.
3. Изменение цен: Как указано в подсказке, цены могут меняться. Если бы отчет формировался "по требованию", то при изменении цены необходимо было бы пересчитывать все предыдущие продажи с новой ценой. В витрине же можно сохранять сумму продажи на момент ее совершения, что дает историческую точность данных.  
  
Однако стоит учесть, что использование триггеров может влиять на производительность при большом объеме операций вставки/обновления/удаления данных, так что решение использовать витрину и триггеры следует принимать, исходя из конкретных условий и требований к системе.