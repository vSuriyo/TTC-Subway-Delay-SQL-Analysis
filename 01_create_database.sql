-- ============================================================
-- 01_create_database.sql
-- Create schema, load raw CSV, and set up staging table
-- ============================================================

USE ttc_subway_delay;

-- ------------------------------------------------------------
-- 1. Create _raw Table
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ttc_subway_delay_raw;

CREATE TABLE ttc_subway_delay_raw (
    id INT,
    report_date DATETIME,
    report_time TIME,
    day_of_week VARCHAR(20),
    station VARCHAR(150),
    incident_code VARCHAR(20),
    min_delay INT,
    min_gap INT,
    bound VARCHAR(10),
    `line` VARCHAR(100),
    vehicle VARCHAR(50)

);

-- ------------------------------------------------------------
-- 2.1 Load CSV Local File into Raw Table -- [ This was Loaded in MariaDB through Konsole ]  
-- ------------------------------------------------------------

LOAD DATA LOCAL INFILE '/home/super_cereal/Projects/ttc-subway-delay/TTC Subway Delay Data since 2025.csv'
INTO TABLE ttc_subway_delay
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    id, 
    report_date, 
    report_time, 
    day_of_week, 
    station, 
    incident_code, 
    min_delay, 
    min_gap, 
    bound, 
    `line`, 
    vehicle
);

-- Verify structure
DESCRIBE BY ttc_subway_delay;

-- ------------------------------------------------------------
-- 2.2 : Create raw Table throught this text editor
-- ------------------------------------------------------------
DROP TABLE IF EXISTS ttc_subway_raw;

CREATE TABLE ttc_subway_raw LIKE ttc_subway_delay;
INSERT INTO ttc_subway_raw SELECT * FROM ttc_subway_delay;

-- ------------------------------------------------------------
-- 3: Create staging table
-- ------------------------------------------------------------

DROP TABLE IF EXISTS stg_subway;
CREATE TABLE stg_subway LIKE ttc_subway_raw;
INSERT INTO stg_subway
SELECT *
FROM ttc_subway_raw;
