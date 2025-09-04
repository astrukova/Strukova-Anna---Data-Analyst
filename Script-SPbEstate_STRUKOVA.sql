-- Решение ad-hoc задач
-- Задача 1. Время активности объявлений
-- отфильтруем аномальные значения
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
-- присвоим категории для регионов 
  region_cat AS (
  SELECT COUNT (f.id) AS count_flats,
  COUNT (f.id) FILTER (WHERE f.rooms = 0) AS count_studio,
  COUNT (f.id) FILTER (WHERE f.is_apartment = 1) AS count_apart,
  -- категоризируем по регионам
  CASE WHEN c.city = 'Санкт-Петербург' THEN 'СПб'
  ELSE 'ЛО'
  END AS region,
  -- категоризируем по времени активности объявления
  CASE WHEN a.days_exposition BETWEEN 0 AND 30 THEN 'до месяца'
  WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'до трех месяцев'
  WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'до полугода'
  WHEN a.days_exposition > 180 THEN 'больше полугода'
  ELSE 'еще в продаже'
  END AS active_days_cat,
  -- расчитаем требуемые характеристики
  ROUND (AVG (f.total_area::NUMERIC),2) AS avg_area,
  ROUND (AVG (a.last_price::NUMERIC/f.total_area::numeric),2) AS avg_area_price, -- ср.цена за кв.м
  ROUND (PERCENTILE_CONT (0.5) WITHIN GROUP (ORDER BY rooms)::numeric,2) AS median_rooms, -- медиана по кол-ву комнат
  ROUND (PERCENTILE_CONT (0.5) WITHIN GROUP (ORDER BY floor)::numeric,2) AS median_floors, -- медиана по этажности
  ROUND (PERCENTILE_CONT (0.5) WITHIN GROUP (ORDER BY balcony)::numeric,2) AS median_balcony -- медиана по кол-ву балконов
  FROM real_estate.flats AS f
  LEFT JOIN real_estate.city AS c ON c.city_id = f.city_id
  LEFT JOIN real_estate.advertisement AS a ON a.id = f.id
  LEFT JOIN real_estate.TYPE AS t ON t.type_id = f.type_id
  WHERE f.id IN (SELECT * FROM filtered_id) AND t.TYPE = 'город' /*AND a.days_exposition IS NOT NULL*/
  GROUP BY region, active_days_cat)
  
  --основной запрос
  SELECT count_flats,
  ROUND (count_studio::NUMERIC*100/count_flats::NUMERIC,4) AS share_studio_pers, -- доля студий от общего количества
  ROUND (count_apart::NUMERIC*100/count_flats::NUMERIC,4) AS share_apartm_pers, -- доля апартаментов от общего количества 
  region, active_days_cat, avg_area, avg_area_price, median_rooms, median_floors, median_balcony
  FROM region_cat;

  -- Задача 2. Сезонность объявлений
-- ДИНАМИКА ПО ПУБЛИКАЦИЯМ ОБЪЯВЛЕНИЙ
  -- вставка, чтобы отсеять аномалии:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ), 
season_advertisement_month AS (
	  SELECT 
	  EXTRACT (MONTH FROM DATE_TRUNC('month', a.first_day_exposition)::date) AS num_month,
	  COUNT (a.id) AS public_flats,
	  ROUND (AVG (a.last_price::NUMERIC/f.total_area::numeric),2) AS avg_area_price, -- ср. стоимость за кв.м.
	  ROUND (AVG (f.total_area)::numeric,2) AS avg_area -- ср. общая площадь
	  FROM real_estate.advertisement AS a
	  LEFT JOIN real_estate.flats AS f ON f.id = a.id
	  LEFT JOIN real_estate.TYPE AS t ON t.type_id = f.type_id
	  WHERE f.id IN (SELECT * FROM filtered_id) AND t.TYPE = 'город' AND a.first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31'
	  GROUP BY num_month),
-- второе вспомогательное СТЕ. 
-- возможно, не самое эстетичное решение, но мне пока так логичнее двигаться по шагам :) 	  
	season_help AS(
	SELECT num_month,
	public_flats,
	SUM (public_flats) OVER ( ) AS total_public_flats,
	avg_area_price,
	avg_area,
	-- категоризируем по временам года
	CASE WHEN num_month = '1' OR num_month = '2' OR num_month = '12' THEN 'зима'
	WHEN num_month = '3' OR num_month = '4' OR num_month = '5' THEN 'весна'
	WHEN num_month = '6' OR num_month = '7' OR num_month = '8' THEN 'лето'
	WHEN num_month = '9' OR num_month = '10' OR num_month = '11' THEN 'осень'
	END AS season
	FROM season_advertisement_month
	ORDER BY public_flats DESC)
-- основной запрос
		SELECT num_month,
		public_flats,
		ROUND (public_flats::numeric/total_public_flats::NUMERIC,2) AS share_pub_flats,
		avg_area_price,
		avg_area,
		season,
		SUM (public_flats) OVER (PARTITION BY season) AS sum_by_season,
		DENSE_RANK () OVER (ORDER BY public_flats DESC, num_month) AS rank_active_public, -- ранг по наибольшей активности публикаций
		DENSE_RANK () OVER (ORDER BY avg_area_price DESC) AS rank_avg_area_price, -- ранг по наибольшей ср. стоимости за кв.м.
		DENSE_RANK () OVER (ORDER BY avg_area DESC) AS rank_avg_area -- ранг по наибольшей общей площади
		FROM season_help
		ORDER BY rank_active_public; 


-- ДИНАМИКА ПО ПРОДАЖАМ 
-- вставка для исключения аномалий
 WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),  
 season_deal AS (
	  SELECT 
	  EXTRACT (MONTH FROM  DATE_TRUNC('month',((a.first_day_exposition + INTERVAL '1 day' * a.days_exposition)::date))::date) AS num_month,
	  COUNT (a.id) AS selled_flats,
	  ROUND (AVG (a.last_price::NUMERIC/f.total_area::numeric),2) AS avg_area_price,
	  ROUND (AVG (f.total_area)::numeric,2) AS avg_area
	  FROM real_estate.advertisement AS a
	  LEFT JOIN real_estate.flats AS f ON f.id = a.id
	  LEFT JOIN real_estate.TYPE AS t ON t.type_id = f.type_id
	  WHERE f.id IN (SELECT * FROM filtered_id) AND a.days_exposition IS NOT NULL AND t.TYPE = 'город' AND a.first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31'
	  GROUP BY num_month),

season_deal_help AS (
	SELECT num_month,
	selled_flats,
	avg_area_price,
	avg_area,
	SUM (selled_flats) OVER ( ) AS total_selled_flats,
	-- категоризируем по временам года
	CASE WHEN num_month = '1' OR num_month = '2' OR num_month = '12' THEN 'зима'
		WHEN num_month = '3' OR num_month = '4' OR num_month = '5' THEN 'весна'
		WHEN num_month = '6' OR num_month = '7' OR num_month = '8' THEN 'лето'
		WHEN num_month = '9' OR num_month = '10' OR num_month = '11' THEN 'осень'
		END AS season
	FROM season_deal
	ORDER BY selled_flats DESC)
-- основной запрос	
SELECT num_month,
		selled_flats,
		ROUND (selled_flats::numeric/total_selled_flats::NUMERIC,2) AS share_pub_flats,
		avg_area_price,
		avg_area,
		season,
		SUM(selled_flats) OVER (PARTITION BY season) AS sum_by_season,
		DENSE_RANK () OVER (ORDER BY selled_flats DESC, num_month) AS rank_active_deals, -- ранг по наибольшей активности публикаций
		DENSE_RANK () OVER (ORDER BY avg_area_price DESC) AS rank_avg_area_price, -- ранг по наибольшей ср. стоимости за кв.м.
		DENSE_RANK () OVER (ORDER BY avg_area DESC) AS rank_avg_area -- ранг по наибольшей общей площади
		FROM season_deal_help
		ORDER BY rank_active_deals;

-- Задача 3. Анализ рынка недвижимости Ленобласти
-- вставка для исключения аномалий
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    ),
 top_stat AS (    
		SELECT c.city,	
		ROUND ((AVG (a.days_exposition) FILTER (WHERE a.days_exposition IS NOT NULL))::NUMERIC,2) AS lenght_public, -- длительность публикации на сайте
		COUNT (f.id) AS count_advert, -- считаем сколько всего объявлений
		COUNT (a.id) FILTER (WHERE days_exposition IS NOT NULL) AS count_selled_flats, -- считаем проданные объекты
		ROUND (AVG (f.total_area::NUMERIC),2) AS avg_area,
		ROUND (AVG (a.last_price::NUMERIC/f.total_area::numeric),2) AS avg_area_price,
		ROUND (PERCENTILE_CONT (0.5) WITHIN GROUP (ORDER BY rooms)::numeric,2) AS median_rooms,
		ROUND (PERCENTILE_CONT (0.5) WITHIN GROUP (ORDER BY floor)::numeric,2) AS median_floors,
		ROUND (PERCENTILE_CONT (0.5) WITHIN GROUP (ORDER BY balcony)::numeric,2) AS median_balcony
		FROM real_estate.city AS c
		LEFT JOIN real_estate.flats AS f ON f.city_id = c.city_id
		LEFT JOIN real_estate.advertisement AS a ON a.id = f.id
		WHERE c.city <> 'Санкт-Петербург'
		GROUP BY c.city
		ORDER BY count_advert DESC
		LIMIT 15
		)
-- основной запрос	
SELECT city,
lenght_public,
count_advert,
ROUND(count_selled_flats::NUMERIC*100/count_advert::NUMERIC,2) AS percent_selled_flats, -- процент проданных объектов
NTILE (3) OVER (ORDER BY lenght_public) AS category_lenght_public,
avg_area,
avg_area_price,
median_rooms,
median_floors,
median_balcony
FROM top_stat;

