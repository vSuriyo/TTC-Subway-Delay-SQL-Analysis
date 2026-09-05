-- ====================================================================
-- 02_exploratory_data.sql
-- Profile : - check for nulls, blanks cells and
--           - investigate missing values in `line` and `bound` columns
-- ====================================================================

-- ------------------------------------------------------------
-- 1: Overall completeness check
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS total_rows,                                                 -- 40656 Total Rows

    SUM(id IS NULL) AS id_null,                                             -- Numerical values
    SUM(report_date IS NULL) AS report_date_null,                           -- 0
    SUM(report_time IS NULL) AS report_time_null,                           -- 0
    SUM(min_delay IS NULL) AS min_delay_null,                               -- 0
    SUM(min_gap IS NULL) AS min_gap_null,                                   -- 0
                                                                            -- 0
           -- String Values                                                                       
    SUM(COALESCE(TRIM(day_of_week), '') = '') AS day_of_week_blank,         -- 0
    SUM(COALESCE(TRIM(station), '') = '') AS station_blank,                 -- 0
    SUM(COALESCE(TRIM(incident_code), '') = '') AS incident_code_blank,     -- 0
    SUM(COALESCE(TRIM(bound), '') = '') AS bound_blank,                     -- 14179 Blank cells
    SUM(COALESCE(TRIM(`line`), '') = '') AS line_blank,                     -- 143 Blank cells
    SUM(COALESCE(TRIM(vehicle), '') = '') AS vehicle_blank                  -- 0
FROM stg_subway;


-- ------------------------------------------------------------
-- 2: Investigate rows with missing values in `line` column
-- ------------------------------------------------------------

-- Investigate if there exists a relationship between Incident Codes and subway line

WITH line_blank AS (
    SELECT
        incident_code,
        min_delay
    FROM stg_subway
    WHERE COALESCE(TRIM(`line`),'') = ''
)
SELECT
    incident_code,
    COUNT (*) AS incident_code_amount,
    SUM(min_delay) AS min_delay_total
FROM line_blank
GROUP BY incident_code
HAVING SUM(min_delay) > 0
ORDER BY min_delay_total DESC;

-- Results : Only the MUI(injury)(5 mins delay) code and MUPAA(No trouble found)(3 Mins delay) code have delay > 0
-- The remanining 141 rows have 0 mins delay thus it is safe to remove

WITH line_rows_to_remove AS (
    SELECT
        incident_code,
        min_delay
    FROM stg_subway
    WHERE COALESCE(TRIM(`line`),'') = ''
    AND COALESCE(min_delay, 0) <= 0
)
SELECT
    incident_code,
    COUNT (*) AS line_rows_to_remove,
    SUM(COALESCE(min_delay,0)) AS total_line_delay_to_remove
FROM line_rows_to_remove
GROUP BY incident_code
ORDER BY
    total_line_delay_to_remove,
    line_rows_to_remove DESC;

SELECT COUNT(*) AS line_rows_to_remove
FROM stg_subway
WHERE COALESCE(TRIM(`line`), '') = ''
  AND COALESCE(min_delay, 0) <= 0;


-- Delete The Empty/Null cells in `line` column where the delay is less or equal to 0
DELETE FROM stg_subway
WHERE COALESCE(TRIM(`line`),'') = ''
AND COALESCE(TRIM(min_delay), 0) <= 0;

-- Inspect the changes/deletion
SELECT 'Raw Count' AS Tables, COUNT(*) total_rows
FROM ttc_subway_raw
UNION ALL
SELECT 'Staging Count' AS Tables , COUNT(*) total_rows
FROM stg_subway;

-- ------------------------------------------------------------
-- 2.1: Investigate and fix the 2 remaining empty `line` cells
-- ------------------------------------------------------------

SELECT *
FROM stg_subway
    WHERE COALESCE(TRIM(`line`),'') = '';
-- 2 Rows needs editing ; id = 6936 and 37440

-- This Method to find the correct subway line is more complete
SELECT
    CASE
        WHEN UPPER(TRIM(station)) LIKE '%QUEEN STATION%' THEN 'Queen station'
        WHEN UPPER(TRIM(station)) LIKE '%KIPLING STATION%' THEN 'Kipling Station'
    END AS target_station,

    TRIM(bound) AS bound,
    TRIM(`line`) AS line_seen,
    COUNT(*) AS times_freq

FROM stg_subway
WHERE
    (
        UPPER(TRIM(station)) LIKE '%QUEEN STATION%'
        OR UPPER(TRIM(station)) LIKE  '%KIPLING STATION%'
    )
    AND COALESCE(TRIM(`line`),'') <> ''

GROUP BY
    target_station,
    bound,
    line_seen

ORDER BY
    target_station,
    bound,
    times_freq DESC;
-- Kipling Station runs on the BD line and Queen Station runs on the YU Line

UPDATE stg_subway
SET
    `line` = CASE
    WHEN id = 6936 THEN 'YU'
    WHEN id = 37440 THEN 'BD'
    ELSE `line`
    END
WHERE
    id IN (6936, 37440)
    AND COALESCE(TRIM(`line`),'') = '';

DROP TABLE IF EXISTS stg_subway_clean;
CREATE TABLE stg_subway_clean LIKE stg_subway;
INSERT INTO stg_subway_clean
SELECT *
FROM stg_subway;

-- ------------------------------------------------------------
-- 3: Investigate rows with missing `bound` directions
-- ------------------------------------------------------------

-- Create a temporary table
DROP TEMPORARY TABLE IF EXISTS tmp_stg_subway_clean;

CREATE TEMPORARY TABLE tmp_stg_subway_clean AS
SELECT *
FROM stg_subway_clean
WHERE COALESCE(TRIM(bound), '') = '';

-- Inspect table integrity
SELECT *
FROM tmp_stg_subway_clean
LIMIT 50;

-- Investigation 1 : Use Groupby to find the most frequent incidents
SELECT
    incident_code,
    COUNT (*) AS incident_code_frequency,
    SUM(min_delay) AS min_delay_total
FROM tmp_stg_subway_clean
WHERE min_delay > 0
GROUP BY incident_code
ORDER BY min_delay_total DESC;

-- (7343/7601)= 97% of the Top 15 most frequent subway incidents halts both Bound Direction
-- Because Both direction are Halted, we can add the Correct Bound Direction corresponding to `Line` direction

-- ---------------------------------------------------------------
-- 3.1: Map the missing `bound` column by using the `line` column
-- Logic:
--   • YU + BD/SHP → 'ALL'  (all four directions halted)
--   • YU only     → 'N,S'  (North/South directions)
--   • BD and/or SHP   → 'W,E'  (West/East directions)
-- ---------------------------------------------------------------

WITH bound_being_filled AS (
    SELECT
        id,
        station,
        `line`,
        bound AS original_bound,

        CASE
            -- If all four directions in bound are halted, it's labelled as ALL
            WHEN `line` LIKE '%YU%' AND (`line` LIKE '%BD%' OR `line` LIKE '%SHP%') THEN 'ALL'
            -- If the `line` is on the Yonge-University Line, Then the Bound column is labelled as N,S instead of Bb
            WHEN `line` LIKE '%YU%' THEN 'N,S'
            -- If the `line` in on the Bloor Danforth Line, then The Bound column is labelled as W,E
            WHEN `line` LIKE '%BD%' THEN 'W,E'
            -- If the `line` is on the Sheppard-Yonge Line, then its Bound column is labelled as W,E
            WHEN `line` LIKE '%SHP%' THEN 'W,E'
            ELSE bound
        END AS new_bound

    FROM stg_subway_clean
    WHERE COALESCE(TRIM(bound),'') = ''
)
SELECT *
FROM bound_being_filled
ORDER BY `line`;
-- Inspections Look Good

-- ------------------------------------------------------------
-- 3.2 Update the Bounds Direction via Transaction Method
-- ------------------------------------------------------------

START TRANSACTION;
UPDATE stg_subway_clean
SET
    bound = CASE
        WHEN `line` LIKE '%YU%' AND (`line` LIKE '%BD%' OR `line` LIKE '%SHP%') THEN 'ALL'
        WHEN `line` LIKE '%YU%' THEN 'N,S'
        WHEN `line` LIKE '%BD%' THEN 'W,E'
        WHEN `line` LIKE '%SHP%' THEN 'W,E'
        ELSE bound
    END
WHERE COALESCE(TRIM(bound),'') = '';

COMMIT;

SELECT *
FROM stg_subway_clean
WHERE COALESCE(TRIM(bound), '') = '';
-- There are 14 leftover unlabelled `bound` direction. After inspection 13 out of 14 are not subway related
-- Only 1 is on the subway line and 13 will be removed

UPDATE stg_subway_clean
SET bound = 'W,E'
WHERE id = 19245;

-- ------------------------------------------------------------
-- 3.3 Clean the Remaining Empty/Null space after inspection
-- ------------------------------------------------------------
START TRANSACTION;

DELETE FROM stg_subway_clean
WHERE COALESCE(TRIM(bound),'') = '';

SELECT *
FROM stg_subway_clean
WHERE COALESCE(TRIM(bound),'') = '';

COMMIT;

-- ------------------------------------------------------------
-- 3.4 Renaming and Continue cleaning the bound column
-- ------------------------------------------------------------

-- There exist some `line` that are not actually part of the main three subway lines, e.g. LRT and Buses
SELECT *
FROM stg_subway_clean
WHERE
    COALESCE(TRIM(`line`),'') NOT LIKE '%BD%'
    AND COALESCE(TRIM(`line`),'')  NOT LIKE  '%YU%'
    AND COALESCE(TRIM(`line`),'')  NOT LIKE  '%SHP%';
-- 7 Lines are incorrect labelled


UPDATE stg_subway_clean
SET
    `line` = CASE
        WHEN UPPER(TRIM(`line`)) = 'LINE 1'
        OR UPPER(TRIM(`line`)) LIKE 'LINE 1 %' THEN 'YU'

        WHEN UPPER(TRIM(`line`)) = 'LINE 2 - BLOOR DANFORTH'
        OR UPPER(TRIM(`line`)) LIKE 'LINE 2 %' THEN 'BD'

        ELSE `line`
    END
WHERE 
    (
        UPPER(TRIM(`line`)) = 'LINE 1'
        OR UPPER(TRIM(`line`)) LIKE 'LINE 1 %'
    )
    OR
    (
        UPPER(TRIM(`line`)) = 'LINE 2'
    OR UPPER(TRIM(`line`)) LIKE 'LINE 2 %'
    );
-- 2 `line` are correctly labelled

-- The remaining 5 lines are not part of the main subway lines, they are part of the maintenance line and LRT and have 0 delay time

START TRANSACTION;

DELETE FROM stg_subway_clean
WHERE
    COALESCE(UPPER(TRIM(`line`)),'') NOT LIKE '%YU%'
    AND COALESCE(UPPER(TRIM(`line`)),'') NOT LIKE '%BD%'
    AND COALESCE(UPPER(TRIM(`line`)),'') NOT LIKE '%SHP%';

SELECT ROW_COUNT() AS deleted_rows;

COMMIT;

select
    COUNT(*) as total_left_over
FROM stg_subway_clean;