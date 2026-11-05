INSERT INTO "WITH last_click AS (
  -- Атрибуция Last Paid Click: берём только последний платный визит пользователя
  SELECT *
  FROM (
    SELECT 
      s.visitor_id,
      CAST(s.visit_date AS DATE) AS visit_date,
      s.source AS utm_source,
      s.medium AS utm_medium,
      s.campaign AS utm_campaign,
      l.lead_id,
      l.amount,
      l.created_at,
      l.closing_reason,
      l.status_id,
      ROW_NUMBER() OVER(PARTITION BY s.visitor_id ORDER BY s.visit_date DESC) AS rn
    FROM sessions s
    LEFT JOIN leads l ON s.visitor_id = l.visitor_id AND l.created_at >= s.visit_date
    WHERE s.medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
  ) t
  WHERE rn = 1 -- Оставляем только самый поздний клик
),
costs AS (
  -- Агрегируем расходы из рекламных кабинетов. Важно указывать ТОЛЬКО нужные колонки!
  SELECT campaign_date, utm_source, utm_medium, utm_campaign, SUM(daily_spent) AS total_cost
  FROM (
    SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent FROM ya_ads
    UNION ALL
    SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent FROM vk_ads
  ) ads
  GROUP BY campaign_date, utm_source, utm_medium, utm_campaign
)
SELECT
  lc.visit_date,
  COUNT(lc.visitor_id) AS visitors_count, 
  lc.utm_source,
  lc.utm_medium,
  lc.utm_campaign,
  c.total_cost AS total_cost, 
  COUNT(lc.lead_id) AS leads_count,
  /* Считаем успешные сделки */
  SUM(CASE WHEN lc.closing_reason = 'Успешно реализовано' OR lc.status_id = 142 THEN 1 ELSE 0 END) AS purchases_count,
  /* Считаем выручку от успешных сделок */
  SUM(CASE WHEN lc.closing_reason = 'Успешно реализовано' OR lc.status_id = 142 THEN lc.amount ELSE 0 END) AS revenue
FROM last_click lc
LEFT JOIN costs c ON  
  lc.visit_date = c.campaign_date -- Связываем дату визита с датой расхода
  AND lc.utm_source = c.utm_source
  AND lc.utm_medium = c.utm_medium
  AND lc.utm_campaign = c.utm_campaign
GROUP BY 
  lc.visit_date,          -- [1]
  lc.utm_source,         -- [3]
  lc.utm_medium,         -- [4]
  lc.utm_campaign,       -- [5]
  total_cost             -- 🔑 Используем вычисленное поле, а не ссылку на таблицу
ORDER BY
  revenue DESC NULLS LAST,
  visit_date ASC,
  visitors_count DESC,
  utm_source ASC,
  utm_medium ASC,
  utm_campaign asc
limit 15" (visit_date,visitors_count,utm_source,utm_medium,utm_campaign,total_cost,leads_count,purchases_count,revenue) VALUES
	 ('2023-06-01',103,'yandex','cpc','freemium',21654,100,25,1654810),
	 ('2023-06-01',78,'yandex','cpc','prof-frontend',57138,73,12,1057000),
	 ('2023-06-01',62,'yandex','cpc','prof-python',33026,61,7,613196),
	 ('2023-06-01',31,'yandex','cpc','base-python',12524,28,7,476021),
	 ('2023-06-01',71,'vk','cpc','prof-python',2028,40,5,355564),
	 ('2023-06-01',80,'vk','cpc','freemium-frontend',3160,43,5,338083),
	 ('2023-06-01',49,'yandex','cpc','prof-java',29490,49,4,284590),
	 ('2023-06-01',40,'yandex','cpc','base-frontend',18061,39,3,268515),
	 ('2023-06-01',51,'vk','cpc','prof-java',3115,23,2,232726),
	 ('2023-06-01',14,'yandex','cpc','prof-data-analytics',10086,14,2,220264);
INSERT INTO "WITH last_click AS (
  -- Атрибуция Last Paid Click: берём только последний платный визит пользователя
  SELECT *
  FROM (
    SELECT 
      s.visitor_id,
      CAST(s.visit_date AS DATE) AS visit_date,
      s.source AS utm_source,
      s.medium AS utm_medium,
      s.campaign AS utm_campaign,
      l.lead_id,
      l.amount,
      l.created_at,
      l.closing_reason,
      l.status_id,
      ROW_NUMBER() OVER(PARTITION BY s.visitor_id ORDER BY s.visit_date DESC) AS rn
    FROM sessions s
    LEFT JOIN leads l ON s.visitor_id = l.visitor_id AND l.created_at >= s.visit_date
    WHERE s.medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
  ) t
  WHERE rn = 1 -- Оставляем только самый поздний клик
),
costs AS (
  -- Агрегируем расходы из рекламных кабинетов. Важно указывать ТОЛЬКО нужные колонки!
  SELECT campaign_date, utm_source, utm_medium, utm_campaign, SUM(daily_spent) AS total_cost
  FROM (
    SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent FROM ya_ads
    UNION ALL
    SELECT campaign_date, utm_source, utm_medium, utm_campaign, daily_spent FROM vk_ads
  ) ads
  GROUP BY campaign_date, utm_source, utm_medium, utm_campaign
)
SELECT
  lc.visit_date,
  COUNT(lc.visitor_id) AS visitors_count, 
  lc.utm_source,
  lc.utm_medium,
  lc.utm_campaign,
  c.total_cost AS total_cost, 
  COUNT(lc.lead_id) AS leads_count,
  /* Считаем успешные сделки */
  SUM(CASE WHEN lc.closing_reason = 'Успешно реализовано' OR lc.status_id = 142 THEN 1 ELSE 0 END) AS purchases_count,
  /* Считаем выручку от успешных сделок */
  SUM(CASE WHEN lc.closing_reason = 'Успешно реализовано' OR lc.status_id = 142 THEN lc.amount ELSE 0 END) AS revenue
FROM last_click lc
LEFT JOIN costs c ON  
  lc.visit_date = c.campaign_date -- Связываем дату визита с датой расхода
  AND lc.utm_source = c.utm_source
  AND lc.utm_medium = c.utm_medium
  AND lc.utm_campaign = c.utm_campaign
GROUP BY 
  lc.visit_date,          -- [1]
  lc.utm_source,         -- [3]
  lc.utm_medium,         -- [4]
  lc.utm_campaign,       -- [5]
  total_cost             -- 🔑 Используем вычисленное поле, а не ссылку на таблицу
ORDER BY
  revenue DESC NULLS LAST,
  visit_date ASC,
  visitors_count DESC,
  utm_source ASC,
  utm_medium ASC,
  utm_campaign asc
limit 15" (visit_date,visitors_count,utm_source,utm_medium,utm_campaign,total_cost,leads_count,purchases_count,revenue) VALUES
	 ('2023-06-01',13,'yandex','cpc','prof-professions-brand',4818,13,3,154287),
	 ('2023-06-20',3,'telegram','cpp','base-java',NULL,1,1,151192),
	 ('2023-06-01',4,'yandex','cpc','dod-php',5964,4,1,150255),
	 ('2023-06-01',4,'yandex','cpc','base-professions-retarget',151,4,1,134100),
	 ('2023-06-07',3,'vk','social','hexlet-blog',NULL,1,1,84000);
