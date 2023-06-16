# Установка и настройка PostgteSQL в контейнере Docker

## Т.к. на прошлом занятии я устанавливал postgresql в контейнере docker, начну с пункта запуска контейнера

1. Запускаем PostgreSQL
```bash
docker exec -it postgre_ubuntu service postgresql start
```

2. Заходим в контейнер Docker
```bash
docker exec -it postgre_ubuntu bash
```

3. Подключаемся к psql
```bash
sudo -i -u postgres psql
```

4. Создаём таблицу с парой строк
```sql
CREATE TABLE test_table (id INT, data VARCHAR(20));
INSERT INTO test_table VALUES (1, 'data1');
INSERT INTO test_table VALUES (2, 'data2');
SELECT * FROM test_table;
```

5. Подключаемся с другого ПК
- вносим изменения в postgresql.conf
```bash
listen_addresses = '*'
```
- вносим изменения в pg_hba.conf
```bash
host    all             all             0.0.0.0/0               scram-sha-256
```
- задаём пароль для пользователя postgres
```sql
ALTER ROLE postgres PASSWORD '*****';
```
- перезапускаем postgres для применения изменений
```bash
sudo service postgresql restart
```
- вносим изменения в firewall
- подключаемся к базе
```bash
psql -h host-ip -U postgres -p 5432
```

6. Удалить контейнер с сервером
```bash
docker rm -f postgre_ubuntu
```

7. Создать его заново
```bash
docker exec -it postgre_ubuntu apt-get install -y postgresql postgresql-contrib
```

8. Подключится снова из контейнера с клиентом к контейнеру с сервером
```bash
docker exec -it postgre_ubuntu bash
```

9. проверить, что данные остались на месте
```sql
SELECT * FROM test_table;
```
 id | data
----|-------
  1 | data1
  2 | data2
(2 rows)
