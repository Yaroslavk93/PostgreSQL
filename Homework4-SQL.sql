--=============== МОДУЛЬ 4. УГЛУБЛЕНИЕ В SQL =======================================
--= ПОМНИТЕ, ЧТО НЕОБХОДИМО УСТАНОВИТЬ ВЕРНОЕ СОЕДИНЕНИЕ И ВЫБРАТЬ СХЕМУ PUBLIC===========
SET search_path TO public;

--======== ОСНОВНАЯ ЧАСТЬ ==============

--ЗАДАНИЕ №1
--База данных: если подключение к облачной базе, то создаёте новую схему с префиксом в --виде фамилии, название должно быть на латинице в нижнем регистре и таблицы создаете --в этой новой схеме, если подключение к локальному серверу, то создаёте новую схему и --в ней создаёте таблицы.
create schema lecture_4

set search_path to lecture_4

--Спроектируйте базу данных, содержащую три справочника:
--· язык (английский, французский и т. п.);
--· народность (славяне, англосаксы и т. п.);
--· страны (Россия, Германия и т. п.).
--Две таблицы со связями: язык-народность и народность-страна, отношения многие ко многим. Пример таблицы со связями — film_actor.
--Требования к таблицам-справочникам:
--· наличие ограничений первичных ключей.
--· идентификатору сущности должен присваиваться автоинкрементом;
--· наименования сущностей не должны содержать null-значения, не должны допускаться --дубликаты в названиях сущностей.
--Требования к таблицам со связями:
--· наличие ограничений первичных и внешних ключей.

--В качестве ответа на задание пришлите запросы создания таблиц и запросы по --добавлению в каждую таблицу по 5 строк с данными.
 
--СОЗДАНИЕ ТАБЛИЦЫ ЯЗЫКИ
CREATE TABLE languages(
	language_id serial primary key,
	language_name varchar(20) not null unique
)


--ВНЕСЕНИЕ ДАННЫХ В ТАБЛИЦУ ЯЗЫКИ
INSERT INTO languages (language_name)
VALUES ('русский'), ('английский'), ('французский'), ('немецкий'), ('испанский')

select * FROM languages l 

--СОЗДАНИЕ ТАБЛИЦЫ НАРОДНОСТИ
CREATE TABLE nationality(
	nationality_id serial primary key,
	nationality_name varchar(20) not null unique
)


--ВНЕСЕНИЕ ДАННЫХ В ТАБЛИЦУ НАРОДНОСТИ
INSERT INTO nationality (nationality_name)
VALUES ('англосаксы'), ('бретонцы'), ('славяне'), ('баварцы'), ('валенсийцы')

select * FROM nationality n 

--СОЗДАНИЕ ТАБЛИЦЫ СТРАНЫ
CREATE TABLE countries(
	country_id serial primary key,
	country_name varchar(20) not null unique
)


--ВНЕСЕНИЕ ДАННЫХ В ТАБЛИЦУ СТРАНЫ
INSERT INTO countries (country_name)
VALUES ('Россия'), ('Франция'), ('Германия'), ('Великобритания'), ('Испания')

select * FROM countries c

--СОЗДАНИЕ ПЕРВОЙ ТАБЛИЦЫ СО СВЯЗЯМИ
CREATE TABLE nationality_countries(
	nationality_id int2 references nationality(nationality_id),
	country_id int2 references countries(country_id),
	primary key (nationality_id, country_id)
)


--ВНЕСЕНИЕ ДАННЫХ В ТАБЛИЦУ СО СВЯЗЯМИ
INSERT INTO nationality_countries (nationality_id, country_id)
VALUES (1, 4), (2, 2), (3, 1), (4, 3), (5, 5)

--СОЗДАНИЕ ВТОРОЙ ТАБЛИЦЫ СО СВЯЗЯМИ
CREATE TABLE languages_nationality(
	language_id int2 references languages(language_id),
	nationality_id int2 references nationality(nationality_id),
	primary key (language_id, nationality_id)
)

select * FROM languages_nationality l

--ВНЕСЕНИЕ ДАННЫХ В ТАБЛИЦУ СО СВЯЗЯМИ
INSERT INTO languages_nationality (language_id, nationality_id)
VALUES (1, 4), (2, 1), (3, 2), (4, 3), (5, 5)


--======== ДОПОЛНИТЕЛЬНАЯ ЧАСТЬ ==============


--ЗАДАНИЕ №1 
--Создайте новую таблицу film_new со следующими полями:
--·   	film_name - название фильма - тип данных varchar(255) и ограничение not null
--·   	film_year - год выпуска фильма - тип данных integer, условие, что значение должно быть больше 0
--·   	film_rental_rate - стоимость аренды фильма - тип данных numeric(4,2), значение по умолчанию 0.99
--·   	film_duration - длительность фильма в минутах - тип данных integer, ограничение not null и условие, что значение должно быть больше 0
--Если работаете в облачной базе, то перед названием таблицы задайте наименование вашей схемы.
create schema lecture_4_extra

set search_path to lecture_4_extra

CREATE TABLE film_new(
	film_id serial primary key,
	film_name varchar(255) not null,
	film_year integer check(film_year > 0),
	film_rental_rate numeric(4, 2) default 0.99,
	film_duration integer not null check(film_duration > 0)
)

--ЗАДАНИЕ №2 
--Заполните таблицу film_new данными с помощью SQL-запроса, где колонкам соответствуют массивы данных:
--·       film_name - array['The Shawshank Redemption', 'The Green Mile', 'Back to the Future', 'Forrest Gump', 'Schindlers List']
--·       film_year - array[1994, 1999, 1985, 1994, 1993]
--·       film_rental_rate - array[2.99, 0.99, 1.99, 2.99, 3.99]
--·   	  film_duration - array[142, 189, 116, 142, 195]
INSERT INTO film_new (film_name, film_year, film_rental_rate, film_duration)
VALUES ('The Shawshank Redemption', 1994, 2.99, 142),
	('The Green Mile', 1999, 0.99, 189),
	('Back to the Future', 1985, 1.99, 116),
	('Forrest Gump', 1994, 2.99, 142),
	('Schindlers List', 1993, 3.99, 195)

select * FROM film_new fn 
	
--ЗАДАНИЕ №3
--Обновите стоимость аренды фильмов в таблице film_new с учетом информации, 
--что стоимость аренды всех фильмов поднялась на 1.41
UPDATE film_new SET film_rental_rate = film_rental_rate + 1.41

SELECT * FROM film_new fn 

--ЗАДАНИЕ №4
--Фильм с названием "Back to the Future" был снят с аренды, 
--удалите строку с этим фильмом из таблицы film_new
DELETE FROM film_new 
WHERE film_name = 'Back to the Future'

SELECT * FROM film_new fn 

--ЗАДАНИЕ №5
--Добавьте в таблицу film_new запись о любом другом новом фильме
INSERT INTO film_new (film_name, film_year, film_rental_rate, film_duration)
VALUES ('The Matrix', 1999, 3.99, 136)

SELECT * FROM film_new fn 

--ЗАДАНИЕ №6
--Напишите SQL-запрос, который выведет все колонки из таблицы film_new, 
--а также новую вычисляемую колонку "длительность фильма в часах", округлённую до десятых
SELECT *, round(film_duration::NUMERIC / 60, 1) as film_duration_hours
FROM film_new fn 


--ЗАДАНИЕ №7 
--Удалите таблицу film_new
DROP TABLE film_new
