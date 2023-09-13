-- Итоговая работа Михальченко Вера DSU - 30

SET search_path TO bookings;

-- 1. В каких городах больше одного аэропорта?

select  
	city, 
	count (city) -- считаю количество городов
from airports
group by 1 -- группирую по городам, потому что есть аггрегатная функция
having count (city) > 1;

-- 2. В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета?
-- - Подзапрос

select 
	distinct f.departure_airport -- создаю уникальный список аэропортов
from flights f
join -- присоединяю к таблице с данными самолёта с максимальной дальностью перелёта
	(select 
		aircraft_code, 
		"range"
	from aircrafts
	order by "range" desc
	limit 1) as a
on f.aircraft_code = a.aircraft_code
;

-- 3. Вывести 10 рейсов с максимальным временем задержки вылета
-- - Оператор LIMIT

select 
	flight_id,
	age (actual_departure, scheduled_departure) as delay -- рассчитываю время задержки
from flights
where status = 'Departured' or status = 'Arrived' -- фильтрую по рейсам, которые уже либо вылетели, либо приземлились
order by delay desc -- создаю список в порядке убывания по времени задержки
limit 10; -- ограничиваю по необходимому количеству

--4. Были ли брони, по которым не были получены посадочные талоны?
-- - Верный тип JOIN

select 
	distinct t1.book_ref, -- уникальный список броней
	b.boarding_no -- номер посадочного, если нет, то null
from tickets t 
join boarding_passes b -- соединяю с данными по посадочным
	on t.ticket_no = b.ticket_no
full outer join tickets t1 -- снова соединяю с данными по броням, чтобы прикрепить номера броней, в которых нет посадочных
	on t.ticket_no = t1.ticket_no
where b.boarding_no is null; -- выбриаю только брони без посадочных

--5. Найдите количество свободных мест для каждого рейса, их % отношение к общему количеству мест в самолете.
-- Добавьте столбец с накопительным итогом - суммарное накопление количества вывезенных пассажиров из каждого аэропорта на каждый день. 
-- Т.е. в этом столбце должна отражаться накопительная сумма - сколько человек уже вылетело из данного аэропорта 
--на этом или более ранних рейсах в течении дня.
-- - Оконная функция
-- - Подзапросы или/и cte

select 
	 f.flight_id,
	 a.aircraft_code,
	 a.all_seats,
	 b.owned_seats,
	 (a.all_seats - b.owned_seats) as free_seats, -- кол-во свободных мест в самолёте
	 (a.all_seats - b.owned_seats)/a.all_seats::float*100 as percent_free_seats, -- процент кол-ва свободных мест по отношению к общему
	 f.departure_airport,
	 f.actual_departure,
	 sum(b.owned_seats) over (partition by f.actual_departure::date, f.departure_airport order by f.actual_departure) as pas_per_day 
	 -- накопительная сумма по нужным параметрам
from flights f 
join
	(select 
		distinct s.aircraft_code,
		count(s.seat_no) over (partition by s.aircraft_code) as all_seats -- считаю общее кол-во мест в самолёте
	from seats s) as a
on a.aircraft_code = f.aircraft_code
join -- соединяю данные, чтобы вычислить количество свободных мест
	(select 
		distinct flight_id,
		count (seat_no) over (partition by flight_id) as owned_seats -- считаю занятое кол-во мест в самолёте
	from boarding_passes) as b
on f.flight_id = b.flight_id
where f.status = 'Departed' or f.status = 'Arrived' -- выбираю рейсы, в которых можно вычислить кол-во вылетевших пассажиров
order by f.actual_departure; -- чтобы проверить верность накопления, отфильтрова по аэропорту

-- 6.Найдите процентное соотношение перелетов по типам самолетов от общего количества.
-- - Подзапрос или окно
-- - Оператор ROUND

select 
	distinct aircraft_code,
	round ((count(flight_id) over (partition by aircraft_code)::float/count (flight_id) over ()::float)*100) as "percent"
	-- вычисляю процент кол-ва перелётов по типу самолёта от общего, подсчитав с помощью окна необходимые для этого значения
from flights;

-- 7. Были ли города, в которые можно  добраться бизнес - классом дешевле, чем эконом-классом в рамках перелета?
-- - CTE

with cte1 as -- выделяю в отдельный столбец стоимость билетов бизнес-класса
	(select
		fare_conditions,
		amount as amount_b,
		flight_id
	from ticket_flights
	where fare_conditions = 'Business'
	),
	cte2 as -- выделяю в отдельный столбец стоимость билетов эконом-класса
	(select
		fare_conditions,
		amount as amount_e,
		flight_id
	from ticket_flights
	where fare_conditions = 'Economy'
	) 
select
	distinct f.arrival_city,
	f.flight_id,
	cte1.amount_b,
	cte2.amount_e
from flights_v f
left join cte1 -- прикрепляю данные по бизнесс классу, сохраняя все рейсы, потому что не везде есть бизнес-клас
on f.flight_id=cte1.flight_id
left join cte2 -- прикрепляю данные по эконом-классу так, чтобы сохранить все рейсы
on f.flight_id=cte2.flight_id
where cte1.amount_b is not null and cte1.amount_b < cte2.amount_e; -- фильтрую по условию задачи


-- 8. Между какими городами нет прямых рейсов?
-- - Декартово произведение в предложении FROM
-- - Самостоятельно созданные представления (если облачное подключение, то без представления)
-- - Оператор EXCEPT

create view all_routes as -- создаю представление, в котром есть все возможные сочетания городов
select
	a.city as dep_city,
	a1.city as arr_city
from airports a, airports a1
where a.city != a1.city
group by a.city, a1.city
order by a.city;

select *
from all_routes;
	
create view straight_routes as -- создаю представление с сочетанием городов, где есть прямые рейсы
select 
	d.dep_city,
	ar.arr_city
from 
	(select 
		f.flight_no,
		f.departure_airport as dep_airport,
		a.airport_name as dep_aiport_name,
		a.city as dep_city
	from flights f
	join airports a
	on f.departure_airport = a.airport_code) as d -- прикрепляю города по аэропорту вылета
join	
	(select 
		f.flight_no,
		f.arrival_airport as arr_airport,
		a.airport_name as arr_aiport_name,
		a.city as arr_city
	from flights f
	join airports a
	on f.arrival_airport = a.airport_code) as ar -- прикрепляю города по аэропорту прилёта
using (flight_no);

select * 
from straight_routes;

select -- удалаяю список маршрутов с прямыми рейсами из списка всевозможных маршрутов
	a.dep_city,
	a.arr_city
from all_routes a
EXCEPT ALL
select
	s.dep_city,
	s.arr_city
from straight_routes s;

-- 9. Вычислите расстояние между аэропортами, связанными прямыми рейсами,
-- сравните с допустимой максимальной дальностью перелетов  в самолетах, обслуживающих эти рейсы *
-- - Оператор RADIANS или использование sind/cosd
-- - CASE

select 
	d.*,
	r."range",
	case -- прописываю условие для сравнения
		when d.distance < r."range" then 'расстояние меньше чем range самолёта'
		else 'придётся дозаправиться'
	end
from 
	(select 
		distinct d.flight_no,
		d.aircraft_code,
		d.dep_aiport_name,
		ar.arr_aiport_name,
		acos (sind(d.latitude)*sind(ar.latitude) + cosd(d.latitude)*cosd(ar.latitude)*cosd(d.longitude - ar.longitude)) *  6371 as distance
		-- вычисляю расстояние между городами
	from 
		(select 
			f.flight_no,
			f.aircraft_code,
			f.departure_airport as dep_airport,
			a.airport_name as dep_aiport_name,
			a.longitude,
			a.latitude
		from flights f
		join airports a
		on f.departure_airport = a.airport_code) as d -- определяю координаты аэропорта вылета, чтобы вычислить расстояние
	join -- соединяю с координатами по аэропорту прилёта
		(select 
			f.flight_no,
			a.longitude,
			a.latitude,
			f.arrival_airport as arr_airport,
			a.airport_name as arr_aiport_name
		from flights f
		join airports a
		on f.arrival_airport = a.airport_code) as ar -- определяю координаты аэропорта прилёта, чтобы вычислить расстояние
	using (flight_no)) as d
join aircrafts r --соединяю с данными по максмальной дальности перелёта в зависимости от самолёта
on d.aircraft_code = r.aircraft_code
;
