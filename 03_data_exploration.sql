-- ====================================================================
-- 03_data_exploration.sql
-- ====================================================================

-- Monthly Delays Trends

WITH monthly AS (
    SELECT
    DATE_FORMAT(report_date, '%Y-%m') AS delay_month, 
    SUM(min_delay) AS min_delay_total
    FROM stg_subway_clean
    GROUP BY delay_month
)
SELECT 
    ROUND(
        (min_delay_total - LAG(min_delay_total) OVER (ORDER BY delay_month))
        / LAG(min_delay_total) OVER (ORDER BY delay_month) * 100,
        1
    ) AS pct_change_prev,

    LAG(min_delay_total) OVER (ORDER BY delay_month) AS prev_month_min,

    delay_month,
    min_delay_total,

    LEAD(min_delay_total) OVER (ORDER BY delay_month) AS next_month_min,
    
    ROUND(
        (LEAD(min_delay_total) OVER (ORDER BY delay_month) - min_delay_total) 
        / min_delay_total * 100,
        1
    ) AS pct_change_next
FROM monthly
ORDER BY delay_month;

-- The back to school month of September is typically the most busiest but has the least delay time
-- Starting from Spring there are fewer delay times heading into Summer

-- Which Stations & Subway Line Are the Worst Offenders

WITH station_delay AS (
    SELECT
        TRIM(UPPER(station)) AS station_clean,
        `line`,
        COUNT(*) AS incident_amount,
        SUM(min_delay) AS min_delay_total
    FROM stg_subway_clean
    GROUP BY
        TRIM(UPPER(station)),
        `line`
)
SELECT
    station_clean,
    `line`,
    min_delay_total,
    RANK() OVER (
        PARTITION BY `line`
        ORDER BY min_delay_total DESC
    ) AS line_ranking
FROM station_delay
ORDER BY 
    `line`, 
    line_ranking
LIMIT 40;

-- Kipling and Victoria Park Station are most Guilty
-- Insights : Kipling Station is the last platform on the West End, thus some delays are to be expected due to tracks changing carts and order
-- Victoria Park Station sits between two stations

SELECT 
    TRIM(station) AS station,
    incident_code,
    COUNT (*) AS row_counts,
    SUM(COALESCE(min_delay, 0)) AS total_delay_time
FROM stg_subway_clean
WHERE UPPER(TRIM(station)) LIKE '%VICTORIA%'
GROUP BY
    TRIM(station),
    incident_code
ORDER BY
    station,
    total_delay_time DESC;
 -- Incident Codes: PUTIS, MUPLB and MUWEA are Victoria Park Station largest reasons for delays by time

 -- Investigate The top 4 culpit stations; Top delay reasons for St. George, Bloor, Kipling, and Kennedy
WITH totals AS (
    SELECT
        TRIM(station) AS station,
        incident_code,
        COUNT(*) AS row_counts,
        SUM(COALESCE(min_delay, 0)) AS total_delay_time
    FROM stg_subway_clean
    WHERE UPPER(TRIM(station)) LIKE '%GEORGE%'
       OR UPPER(TRIM(station)) LIKE '%BLOOR%'
       OR UPPER(TRIM(station)) LIKE '%KIPLING%'
       OR UPPER(TRIM(station)) LIKE '%KENNEDY%'
    GROUP BY
        TRIM(station),
        incident_code
),
ranked AS (
    SELECT
        *,
        RANK() OVER (
            PARTITION BY station
            ORDER BY total_delay_time DESC
        ) AS delay_rank
    FROM totals
)
SELECT
    station,
    incident_code,
    row_counts,
    total_delay_time,
    ROUND(
        100 * total_delay_time / NULLIF(SUM(total_delay_time) OVER (PARTITION BY station), 0),
        1
    ) AS pct_of_station_delay
FROM ranked
WHERE delay_rank <= 10
ORDER BY
    station,
    delay_rank;
-- St.George, Bloor, Kennedy interchange top incidents SUDP, SUO : Disoderly Patrons, Security

-- Apply Pareto code
WITH incident_summary AS (
    SELECT
        TRIM(incident_code) AS incident_code,
        COUNT(*) AS incident_count,
        SUM(COALESCE(min_delay,0)) AS total_delay
    FROM stg_subway_clean
    WHERE COALESCE(TRIM(incident_code),'') <> ''
    AND COALESCE(min_delay,0) > 0
    GROUP BY TRIM(incident_code)
),
cumm AS (
    SELECT
    incident_code,
    incident_count,
    total_delay,

    ROUND(
        total_Delay / NULLIF(SUM(total_delay) OVER (), 0) * 100,
        2
    ) AS delay_pct,

    SUM(total_delay) OVER (
        ORDER BY total_delay DESC, incident_code
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_delay,

    SUM(total_delay) OVER () AS grand_total_delay
FROM incident_summary
)
SELECT
    incident_code,
    incident_count,
    total_delay,
    delay_pct,

    ROUND(
        cumulative_delay / NULLIF(grand_total_delay, 0) * 100,
        2
    ) AS cumulative_delay_pct,

    RANK() OVER (
        ORDER BY incident_count DESC,
        total_delay DESC,
        incident_code ) AS frequent_rank,

    CASE
        WHEN COALESCE(
            Lag(cumulative_delay) OVER (
                ORDER BY total_delay DESC,
                incident_code),
                0
            ) < (grand_total_delay * 0.80)
        THEN 1
        ELSE 0
    END AS top_80_pareto
FROM cumm
ORDER BY total_delay DESC, incident_code;

-- 3/4 Top most frequent delay are cause disorderly patrons and security issues on and off Track level
-- 2/5 Top most frequent delay are cause by injuries
-- Only the 6th is door jammed and communications errors