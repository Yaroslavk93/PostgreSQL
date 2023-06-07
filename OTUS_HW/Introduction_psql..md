# **Настройка Docker, установка Ubuntu и PostgreSQl**


1. Установика Docker
- Проверяем установленную версию:
     ```bash
     docker version
     ```
     
    
2. Загрузка последней версии Ubuntu LTS с Docker Hub
     ```bash
     docker pull ubuntu:latest
     ```

3. Создаём контейнер Docker на основе образа Ubuntu
    ```bash
    docker run -d -it --name postgre_ubuntu ubuntu
    ```

4. Обновляем список пакетов в контейнере
    ```bash
    docker exec -it postgre_ubuntu apt-get update
    ```

5. Устанавливаем PostgreSQL в контейнер с Ubuntu
    ```bash
    docker exec -it postgre_ubuntu apt-get install -y postgresql postgresql-contrib
    ```

6. Запускаем PostgreSQL
    ```bash
    docker exec -it postgre_ubuntu service postgresql start
    ```

7. Заходим в контейнер Docker
    ```bash
    docker exec -it ubuntu_container bash
    ```


# **Работа с транзакциями**

1. Сделать в первой сессии новую таблицу и наполнить ее данными
- psql_1   
    ```sql
    CREATE TABLE persons(id SERIAL, first_name TEXT, second_name TEXT);
    INSERT INTO persons(first_name, second_name) VALUES('ivan', 'ivanov');
    INSERT INTO persons(first_name, second_name) VALUES('petr', 'petrov');
    COMMIT;
    ```
2. Посмотреть текущий уровень изоляции: 
    ```sql
    SHOW TRANSACTION ISOLATION LEVEL;
    ```
    ```bash
    transaction_isolation
    -----------------------
    read committed
    (1 row)
    ```

3. Начать новую транзакцию в обоих сессиях с дефолтным (не меняя) уровнем изоляции
- psql_1
    ```sql
    BEGIN;
    ```
- psql_2
    ```sql
    BEGIN;
    ```

4. В первой сессии добавить новую запись
- psql_1
    ```sql
    INSERT INTO persons(first_name, second_name) VALUES('sergey', 'sergeev');
    ```

5. Сделать select * from persons во второй сессии
- psql_2
    ```sql
    SELECT * FROM persons;
    ```
- Видите ли вы новую запись и если да то почему?
    id | first_name | second_name
    ---|------------|-------------
     1 | ivan       | ivanov
     2 | petr       | petrov
    (2 rows)

    _В этом месте новая запись, которая была добавлена в первой сессии, не должна отображаться, поскольку еще не закоммитили транзакцию в первой сессии._

6. Завершить первую транзакцию - commit;
psql_1
    ```sql
    COMMIT;
    ```
- Сделать select * from persons во второй сессии
psql_2
    ```sql
    SELECT * FROM persons;
    ```
- Видите ли вы новую запись и если да то почему?
     id | first_name | second_name
    ----|------------|-------------
      1 | ivan       | ivanov
      2 | petr       | petrov
      3 | sergey     | sergeev
    (3 rows)

    _Теперь новая запись видна, поскольку транзакция в первой сессии была закоммитирована._

- Завершите транзакцию во второй сессии
psql_2
    ```sql
    COMMIT;
    ```

7. Начать новые но уже repeatable read транзакции
    ```sql
    BEGIN;
    SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    ```

8. В первой сессии добавить новую запись
    ```sql
    INSERT INTO persons(first_name, second_name) VALUES('sveta', 'svetova');
    ```

9. Сделать select * from persons во второй сессии
    ```sql
    SELECT * FROM persons;
    ```
- Видите ли вы новую запись и если да то почему?
     id | first_name | second_name
    ----|------------|-------------
      1 | ivan       | ivanov
      2 | petr       | petrov
      3 | sergey     | sergeev
    (3 rows)

    _В данном случае новые данные не отобразятся, по скольку не закоммитили транзакции в 1й и 2й сессиях_

10. Завершить первую транзакцию
psql_1
    ```sql
    COMMIT;
    ```
- Сделать select * from persons во второй сессии
    ```sql
    SELECT * FROM persons;
    ```
- Видите ли вы новую запись и если да то почему?
     id | first_name | second_name
    ----|------------|-------------
      1 | ivan       | ivanov
      2 | petr       | petrov
      3 | sergey     | sergeev
    (3 rows)

    _Несмотря на то, что транзакция в первой сессии была закоммитирована, новая запись не должна отображаться, поскольку уровень изоляции REPEATABLE READ гарантирует, что мы продолжаем видеть состояние данных на момент начала транзакции._

11. Завершить вторую транзакцию
psql_2
    ```sql
    COMMIT;
    ```
- Сделать select * from persons во второй сессии
    ```sql
    SELECT * FROM persons;
    ```
- Видите ли вы новую запись и если да то почему?
     id | first_name | second_name
    ----|------------|-------------
      1 | ivan       | ivanov
      2 | petr       | petrov
      3 | sergey     | sergeev
      4 | sveta      | svetova
    (4 rows)

    _Теперь мы видем все записи, включая последнюю, которую я добавил в первой сессии, поскольку транзакция была завершена, и я начал новую транзакцию с обновленным состоянием данных._
