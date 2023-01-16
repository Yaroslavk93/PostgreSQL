--Задание 1
--Какие самолеты имеют более 50 посадочных мест?
SELECT DISTINCT a.model as "Модель самолёта", count(s.seat_no) as "Кол-во мест" FROM seats s 
JOIN aircrafts a ON s.aircraft_code = a.aircraft_code
GROUP BY a.model  
HAVING count(s.seat_no) > 50


--Задание 2
--В каких аэропортах есть рейсы, в рамках которых можно добраться бизнес - классом дешевле, чем эконом - классом?
--(CTE)
WITH cte1 as(
	SELECT flight_id, fare_conditions, max(amount) as ae from ticket_flights tf
	WHERE fare_conditions = 'Economy'
	GROUP BY flight_id, fare_conditions),
cte2 as(
	SELECT flight_id, fare_conditions, min(amount) as ab from ticket_flights tf
	WHERE fare_conditions = 'Business'
	GROUP BY flight_id, fare_conditions)
SELECT a.airport_name FROM airports a 
JOIN flights f ON f.departure_airport = a.airport_code
JOIN cte1 ON f.flight_id = cte1.flight_id
JOIN cte2 ON f.flight_id = cte2.flight_id
WHERE cte1.ae > cte2.ab


--Задание 3
--Есть ли самолеты, не имеющие бизнес - класса?
--(array_agg)
SELECT a.model as "Самолёты без Бизнес-класса"
	FROM seats s 
JOIN aircrafts a ON a.aircraft_code = s.aircraft_code
GROUP BY a.model
HAVING 'Business' != ALL(array_agg(DISTINCT s.fare_conditions)) 



--Задание 4
--Найдите количество занятых мест для каждого рейса, 
--процентное отношение количества занятых мест к общему количеству мест в самолете, 
--добавьте накопительный итог вывезенных пассажиров по каждому аэропорту на каждый день.
--(Оконная функция; Подзапрос)
SELECT bp.flight_id as "№ рейса",
		count(bp.seat_no) as "Кол-во занятых мест",
		concat((round((count(bp.seat_no)::NUMERIC / t1.seat::NUMERIC), 2) * 100)::SMALLINT, ' %') as "% соотношение мест",
		t2.airport as "Код аэропорта", t2.dt::date as "Дата",
		sum(count(bp.seat_no)) over (PARTITION BY t2.dt::date, t2.airport ORDER BY t2.dt) as "Кол-во вывезенных людей"
FROM boarding_passes bp
JOIN (SELECT f.flight_id as id, count(s.seat_no) as seat  
		FROM seats s 
		JOIN flights f ON f.aircraft_code = s.aircraft_code
		GROUP BY f.flight_id ORDER BY f.flight_id) t1 ON t1.id = bp.flight_id
JOIN (SELECT f2.flight_id as id, 
			f2.departure_airport as airport, 
			f2.actual_departure as dt 
		FROM flights f2) t2 ON t2.id = bp.flight_id 
GROUP BY bp.flight_id, t1.seat, t2.airport, t2.dt


--Задание 5
--Найдите процентное соотношение перелетов по маршрутам от общего количества перелетов. 
--Выведите в результат названия аэропортов и процентное отношение.
--(Оконная функция; Оператор ROUND)
SELECT a.airport_name as "Название аэропорта",
	count(f.flight_id) t,
	(SELECT count(f2.flight_id) FROM flights f2),
	round((count(f.flight_id)::NUMERIC / (SELECT count(f2.flight_id)::NUMERIC FROM flights f2)) * 100 , 2)
FROM airports a
JOIN flights f ON f.departure_airport = a.airport_code 
GROUP BY 1	
	


--Задание 6
--Выведите количество пассажиров по каждому коду сотового оператора, 
--если учесть, что код оператора - это три символа после +7
SELECT substring(t.contact_data ->> 'phone', 3, 3) as "Код оператора",
	count(t.passenger_id) as "Кол-во пассажиров" 
FROM tickets t
GROUP BY 1
	

	
	
--Задание 7
--Между какими городами не существует перелетов?
--(Декартово произведение; Оператор EXCEPT)
SELECT a.city , a2.city
FROM airports a, airports a2
WHERE a.city != a2.city
EXCEPT
SELECT DISTINCT r.departure_city, r.arrival_city
FROM routes r



--Задание 8
--Классифицируйте финансовые обороты (сумма стоимости билетов) по маршрутам:
--До 50 млн - low
--От 50 млн включительно до 150 млн - middle
--От 150 млн включительно - high
--Выведите в результат количество маршрутов в каждом классе.
--(Оператор CASE)
WITH cte1 as( 
	SELECT tf.flight_id as id,
		concat(f.departure_airport, '-', f.arrival_airport) as route, 
		sum(tf.amount) as amount  
	FROM ticket_flights tf
	JOIN flights f ON tf.flight_id = f.flight_id 
	GROUP BY 1, 2),
cte2 as (
	SELECT cte1.route, 
		sum(cte1.amount)  
	FROM cte1
	GROUP BY 1)	
SELECT count(CASE WHEN cte2.sum < 50000000 THEN 'low' END) as low,
	count(CASE WHEN cte2.sum >= 50000000 AND cte2.sum < 150000000 THEN 'middle' END) as middle,
	count(CASE WHEN cte2.sum >= 150000000 THEN 'high' END) as high
FROM cte2
	





--Задание 9
--Выведите пары городов между которыми расстояние более 5000 км.
--(Оператор RADIANS или использование sind/cosd)
--d = arccos {sin(latitude_a)·sin(latitude_b) + 
--cos(latitude_a)·cos(latitude_b)·cos(longitude_a - longitude_b)}
WITH cte as(
	SELECT a.city as city1, a.longitude as long1, a.latitude as lat1,
		a2.city as city2, a2.longitude as long2, a2.latitude as lat2
	FROM airports a, airports a2  
	WHERE a.city != a2.city)
SELECT cte.city1, cte.city2 
FROM cte
WHERE acos(sind(cte.lat1) * sind(cte.lat2) 
	+ cosd(cte.lat1) * cosd(cte.lat2) * cosd(cte.long1 - cte.long2)) * 6371 > 5000   



