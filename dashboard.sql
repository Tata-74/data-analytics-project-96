1. -- CTE: список платных медиа-каналов для сопоставления
WITH paid_mediums AS (
    SELECT unnest(ARRAY['cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social']) as utm_medium
), 
ranked_sessions AS (
    SELECT 
        visitor_id,
        visit_date,
        source as utm_source,
        medium as utm_medium,
        campaign as utm_campaign,
        content as utm_content,
        ROW_NUMBER() OVER (
            PARTITION BY visitor_id 
            ORDER BY 
                CASE WHEN p.utm_medium IS NOT NULL THEN 1 ELSE 2 END,
                visit_date DESC
        ) as rn -- CTE: ранжирование сессий по каждому посетителю — приоритет платным каналам, затем по дате визита
    FROM sessions s
    LEFT JOIN paid_mediums p ON LOWER(s.medium) = p.utm_medium
),
last_paid_clicks AS (
    SELECT *
    FROM ranked_sessions
    WHERE rn = 1 AND utm_medium IN (SELECT utm_medium FROM paid_mediums)
), -- CTE: выбираем последнюю сессию с платным каналом для каждого посетителя
leads_after_click AS (
    SELECT DISTINCT ON (l.visitor_id)
        l.visitor_id,
        l.lead_id,
        l.created_at,
        l.amount,
        l.closing_reason,
        l.status_id
    FROM leads l
    JOIN last_paid_clicks lpc ON l.visitor_id = lpc.visitor_id
    WHERE l.created_at >= lpc.visit_date
    ORDER BY l.visitor_id, l.created_at ASC
) -- CTE: первый лид после платного клика (по времени создания) для каждого посетителя
-- Основной запрос: связываем последний платный клик с первым лидом после него
SELECT 
    lpc.visitor_id,
    lpc.visit_date,
    lpc.utm_source,
    lpc.utm_medium,
    lpc.utm_campaign,
    lac.lead_id,
    lac.created_at,
    lac.amount,
    lac.closing_reason,
    lac.status_id
FROM last_paid_clicks lpc
LEFT JOIN leads_after_click lac ON lpc.visitor_id = lac.visitor_id
ORDER BY 
    lac.amount DESC NULLS LAST,
    lpc.visit_date ASC,
    lpc.utm_source ASC,
    lpc.utm_medium ASC,
    lpc.utm_campaign asc;

2. -- CTE: агрегация расходы по дням и UTM‑параметрам из VK Ads и Яндекс Директ
WITH ad_spend AS (
    SELECT 
        campaign_date::date AS visit_date,
        utm_source AS source,
        utm_medium AS medium,
        utm_campaign AS campaign,
        utm_content AS content,
        SUM(daily_spent) AS total_cost
    FROM (
        SELECT campaign_date, utm_source, utm_medium, utm_campaign, utm_content, daily_spent 
        FROM vk_ads
        UNION ALL
        SELECT campaign_date, utm_source, utm_medium, utm_campaign, utm_content, daily_spent 
        FROM ya_ads
    ) ads
    GROUP BY 1, 2, 3, 4, 5
), 
-- для каждого посетителя первый лид по времени создания
first_lead_per_visitor AS (
    SELECT 
        visitor_id,
        lead_id,
        amount,
        closing_reason,
        status_id,
        created_at::date AS lead_date,
        ROW_NUMBER() OVER(PARTITION BY visitor_id ORDER BY created_at ASC) as rn
    FROM leads
), 
-- обогащение сессии данными о первом лиде посетителя
sessions_enriched AS (
    SELECT 
        s.visitor_id,
        s.visit_date::date AS visit_date,
        s.source,
        s.medium,
        s.campaign,
        s.content,
        l.lead_id,
        l.amount,
        l.closing_reason,
        l.status_id
    FROM sessions s
    LEFT JOIN first_lead_per_visitor l ON l.visitor_id = s.visitor_id AND l.rn = 1
)
-- основной запрос: объединение данных по визитам и расходам, считаем ключевые метрики
SELECT 
    COALESCE(se.visit_date, ad.visit_date) AS visit_date,
    COUNT(DISTINCT se.visitor_id) AS visitors_count,
    COALESCE(se.source, '') AS utm_source,
    COALESCE(se.medium, '') AS utm_medium,
    COALESCE(se.campaign, '') AS utm_campaign,
    COALESCE(ad.total_cost, 0)::numeric(18, 2) AS total_cost,
    COUNT(se.lead_id) FILTER (WHERE se.lead_id IS NOT NULL) AS leads_count,
    COUNT(se.lead_id) FILTER (
        WHERE se.lead_id IS NOT NULL 
          AND (se.closing_reason = 'Успешно реализовано' OR se.status_id = 142)
    ) AS purchases_count,
    SUM(
        CASE 
            WHEN se.lead_id IS NOT NULL 
                 AND (se.closing_reason = 'Успешно реализовано' OR se.status_id = 142)
            THEN se.amount ELSE 0 
        END
    )::numeric(18, 2) AS revenue
FROM sessions_enriched se
FULL OUTER JOIN ad_spend ad 
    ON se.visit_date = ad.visit_date
   AND COALESCE(se.source, '') = COALESCE(ad.source, '')
   AND COALESCE(se.medium, '') = COALESCE(ad.medium, '')
   AND COALESCE(se.campaign, '') = COALESCE(ad.campaign, '')
   AND COALESCE(se.content, '') = COALESCE(ad.content, '')
   GROUP BY
COALESCE(se.visit_date, ad.visit_date), 
COALESCE(se.source, ''), 
COALESCE(se.medium, ''), 
COALESCE(se.campaign, ''), 
COALESCE(ad.total_cost, 0)
ORDER BY 
    revenue DESC NULLS LAST, 
    visitors_count DESC, 
    total_cost asc;

3.WITH ad_spend AS (
    -- объединяем расходы из VK и Яндекс
    SELECT 
        campaign_date::date AS visit_date,
        utm_source AS source,
        utm_medium AS medium,
        utm_campaign AS campaign,
        utm_content AS content,
        SUM(daily_spent) AS total_cost
    FROM (
        SELECT campaign_date, utm_source, utm_medium, utm_campaign, utm_content, daily_spent FROM vk_ads
        UNION ALL
        SELECT campaign_date, utm_source, utm_medium, utm_campaign, utm_content, daily_spent FROM ya_ads
    ) ads
    GROUP BY 1, 2, 3, 4, 5
),
first_lead_per_visitor AS (
    -- берём первый лид на посетителя (чтобы не считать повторные лиды одного пользователя)
    SELECT 
        visitor_id,
        lead_id,
        amount,
        closing_reason,
        status_id,
        created_at::date AS lead_date,
        ROW_NUMBER() OVER (PARTITION BY visitor_id ORDER BY created_at ASC) AS rn
    FROM leads
),
sessions_enriched AS (
    -- сессии + первый лид
    SELECT 
        s.visitor_id,
        s.visit_date::date AS visit_date,
        s.source,
        s.medium,
        s.campaign,
        s.content,
        l.lead_id,
        l.amount,
        l.closing_reason,
        l.status_id
    FROM sessions s
    LEFT JOIN first_lead_per_visitor l ON l.visitor_id = s.visitor_id AND l.rn = 1
),
base AS (
    -- базовая агрегация по дням и UTM
    SELECT
        COALESCE(se.visit_date, ad.visit_date) AS visit_date,
        COALESCE(se.source, '') AS utm_source,
        COALESCE(se.medium, '') AS utm_medium,
        COALESCE(se.campaign, '') AS utm_campaign,
        COUNT(DISTINCT se.visitor_id) AS visitors_count,
        COALESCE(SUM(ad.total_cost), 0) AS total_cost,
        COUNT(se.lead_id) FILTER (WHERE se.lead_id IS NOT NULL) AS leads_count,
        COUNT(se.lead_id) FILTER (
            WHERE se.lead_id IS NOT NULL 
              AND (se.closing_reason = 'Успешно реализовано' OR se.status_id = 142)
        ) AS purchases_count,
        COALESCE(SUM(
            CASE 
                WHEN se.lead_id IS NOT NULL 
                     AND (se.closing_reason = 'Успешно реализовано' OR se.status_id = 142)
                THEN se.amount ELSE 0 
            END
        ), 0) AS revenue
    FROM sessions_enriched se
    FULL OUTER JOIN ad_spend ad 
        ON se.visit_date = ad.visit_date
       AND COALESCE(se.source, '') = COALESCE(ad.source, '')
       AND COALESCE(se.medium, '') = COALESCE(ad.medium, '')
       AND COALESCE(se.campaign, '') = COALESCE(ad.campaign, '')
       AND COALESCE(se.content, '') = COALESCE(ad.content, '')
    GROUP BY
        COALESCE(se.visit_date, ad.visit_date),
        COALESCE(se.source, ''),
        COALESCE(se.medium, ''),
        COALESCE(se.campaign, '')
)
SELECT
    visit_date,
    utm_source,
    utm_medium,
    utm_campaign,
    visitors_count,
    total_cost,
    leads_count,
    purchases_count,
    revenue,
    -- конверсии
    CASE WHEN visitors_count > 0 THEN leads_count::numeric / visitors_count ELSE 0 END AS conv_visitors_to_leads,
    CASE WHEN leads_count > 0 THEN purchases_count::numeric / leads_count ELSE 0 END AS conv_leads_to_purchases,
    -- метрики
    CASE WHEN visitors_count > 0 THEN total_cost::numeric / NULLIF(visitors_count, 0) ELSE 0 END AS cpu,
    CASE WHEN leads_count > 0 THEN total_cost::numeric / NULLIF(leads_count, 0) ELSE 0 END AS cpl,
    CASE WHEN purchases_count > 0 THEN total_cost::numeric / NULLIF(purchases_count, 0) ELSE 0 END AS cppu,
    CASE WHEN total_cost > 0 THEN ((revenue - total_cost)::numeric / NULLIF(total_cost, 0)) * 100 ELSE 0 END AS roi_percent,
    -- временные периоды (для фильтров и группировки в Preset)
    DATE_TRUNC('week', visit_date)::date AS week_start,
    DATE_TRUNC('month', visit_date)::date AS month_start
FROM base
ORDER BY visit_date DESC;
