-- ============================================
-- STEP 3: The new database design (STAR SCHEMA)
-- A star schema is made for ANSWERING QUESTIONS (analytics).
--   - 1 fact table in the middle: fact_encounters (one row per encounter)
--   - dimension tables around it: date, patient, provider,
--     specialty, department, encounter type, diagnosis, procedure
--   - 2 bridge tables for diagnoses and procedures
--     (an encounter can have MANY of them)
--
-- Every dimension has a SURROGATE KEY (..._key): a new number made
-- by the data warehouse, separate from the hospital's own ID (..._id).
--
-- This file only creates EMPTY tables. 03_etl_load.sql fills them.
-- It deletes and rebuilds the database, so it is safe to run again.
-- ============================================

DROP DATABASE IF EXISTS healthcare_star;
CREATE DATABASE healthcare_star;
USE healthcare_star;

-- ============================================
-- DIMENSION 1: dim_date (WHEN)
-- One row per calendar day. date_key looks like 20240510,
-- so it is a number that is easy to read and fast to join.
-- Year, quarter and month are calculated once here, so queries
-- never need DATE_FORMAT() again.
-- ============================================
CREATE TABLE dim_date (
    date_key       INT PRIMARY KEY,         -- e.g. 20240510
    calendar_date  DATE NOT NULL,
    year           INT NOT NULL,
    quarter        INT NOT NULL,            -- 1 to 4
    month          INT NOT NULL,            -- 1 to 12
    month_name     VARCHAR(10) NOT NULL,    -- 'May'
    year_and_month CHAR(7) NOT NULL,        -- '2024-05'
    day_of_month   INT NOT NULL,
    day_name       VARCHAR(10) NOT NULL,    -- 'Friday'
    is_weekend     TINYINT NOT NULL         -- 1 = Saturday or Sunday
);

-- ============================================
-- DIMENSION 2: dim_patient (WHO)
-- age_group is calculated during the load (ETL),
-- e.g. 'Child 0-4', so analysts can group patients easily.
-- ============================================
CREATE TABLE dim_patient (
    patient_key    INT AUTO_INCREMENT PRIMARY KEY,   -- surrogate key
    patient_id     INT NOT NULL UNIQUE,              -- ID from the hospital system
    first_name     VARCHAR(100),
    last_name      VARCHAR(100),
    gender         CHAR(1),
    date_of_birth  DATE,
    age_group      VARCHAR(20),
    mrn            VARCHAR(20)
);

-- ============================================
-- DIMENSION 3: dim_specialty (WHAT KIND OF CARE)
-- ============================================
CREATE TABLE dim_specialty (
    specialty_key  INT AUTO_INCREMENT PRIMARY KEY,
    specialty_id   INT NOT NULL UNIQUE,
    specialty_name VARCHAR(100),
    specialty_code VARCHAR(10)
);

-- ============================================
-- DIMENSION 4: dim_department (WHERE)
-- ============================================
CREATE TABLE dim_department (
    department_key  INT AUTO_INCREMENT PRIMARY KEY,
    department_id   INT NOT NULL UNIQUE,
    department_name VARCHAR(100),
    floor           INT,
    capacity        INT
);

-- ============================================
-- DIMENSION 5: dim_provider (BY WHOM)
-- Denormalized: the specialty and department NAMES are copied in,
-- so a question about providers needs no extra JOIN.
-- ============================================
CREATE TABLE dim_provider (
    provider_key    INT AUTO_INCREMENT PRIMARY KEY,
    provider_id     INT NOT NULL UNIQUE,
    provider_name   VARCHAR(200),       -- 'James Chen'
    credential      VARCHAR(20),        -- MD, RD
    specialty_name  VARCHAR(100),       -- copied from specialties
    department_name VARCHAR(100)        -- copied from departments
);

-- ============================================
-- DIMENSION 6: dim_encounter_type (WHAT KIND OF VISIT)
-- Outpatient, Inpatient, ER
-- ============================================
CREATE TABLE dim_encounter_type (
    encounter_type_key  INT AUTO_INCREMENT PRIMARY KEY,
    encounter_type_name VARCHAR(50) NOT NULL UNIQUE
);

-- ============================================
-- DIMENSION 7 and 8: dim_diagnosis and dim_procedure
-- Used through the bridge tables below.
-- ============================================
CREATE TABLE dim_diagnosis (
    diagnosis_key     INT AUTO_INCREMENT PRIMARY KEY,
    diagnosis_id      INT NOT NULL UNIQUE,
    icd10_code        VARCHAR(10),
    icd10_description VARCHAR(200)
);

CREATE TABLE dim_procedure (
    procedure_key   INT AUTO_INCREMENT PRIMARY KEY,
    procedure_id    INT NOT NULL UNIQUE,
    cpt_code        VARCHAR(10),
    cpt_description VARCHAR(200)
);

-- ============================================
-- FACT TABLE: fact_encounters
-- GRAIN = one row per encounter (one hospital visit).
-- It holds:
--   - keys to every dimension (who, when, where, what kind)
--   - PRE-AGGREGATED metrics: numbers calculated ONCE during the load,
--     so queries just read them instead of joining and counting.
-- ============================================
CREATE TABLE fact_encounters (
    encounter_key        INT AUTO_INCREMENT PRIMARY KEY,
    encounter_id         INT NOT NULL UNIQUE,    -- ID from the hospital system

    -- Keys to the dimensions
    encounter_date_key   INT NOT NULL,
    discharge_date_key   INT,
    patient_key          INT NOT NULL,
    provider_key         INT NOT NULL,
    specialty_key        INT NOT NULL,   -- stored directly: no providers -> specialties chain
    department_key       INT NOT NULL,
    encounter_type_key   INT NOT NULL,

    -- Exact times (needed for the 30-day readmission rule)
    encounter_datetime   DATETIME,
    discharge_datetime   DATETIME,

    -- Pre-aggregated metrics
    diagnosis_count      INT NOT NULL DEFAULT 0,             -- how many diagnoses
    procedure_count      INT NOT NULL DEFAULT 0,             -- how many procedures
    total_claim_amount   DECIMAL(12,2) NOT NULL DEFAULT 0,   -- money asked
    total_allowed_amount DECIMAL(12,2) NOT NULL DEFAULT 0,   -- money accepted
    length_of_stay_hours INT,                                -- discharge - admission
    is_readmitted_30_days TINYINT NOT NULL DEFAULT 0,        -- 1 = inpatient again within 30 days

    FOREIGN KEY (encounter_date_key) REFERENCES dim_date(date_key),
    FOREIGN KEY (discharge_date_key) REFERENCES dim_date(date_key),
    FOREIGN KEY (patient_key)        REFERENCES dim_patient(patient_key),
    FOREIGN KEY (provider_key)       REFERENCES dim_provider(provider_key),
    FOREIGN KEY (specialty_key)      REFERENCES dim_specialty(specialty_key),
    FOREIGN KEY (department_key)     REFERENCES dim_department(department_key),
    FOREIGN KEY (encounter_type_key) REFERENCES dim_encounter_type(encounter_type_key)
);

-- Indexes for the columns my 4 questions group or filter by
-- (MySQL already indexes every primary key and foreign key)
CREATE INDEX idx_fact_date_specialty ON fact_encounters(encounter_date_key, specialty_key);
CREATE INDEX idx_fact_type_specialty ON fact_encounters(encounter_type_key, specialty_key);

-- ============================================
-- BRIDGE TABLES: many-to-many links
-- One encounter can have MANY diagnoses and MANY procedures.
-- Putting them in the fact table would break the grain
-- (one row per encounter), so they stay in their own small tables.
-- ============================================
CREATE TABLE bridge_encounter_diagnoses (
    encounter_key      INT NOT NULL,
    diagnosis_key      INT NOT NULL,
    diagnosis_sequence INT,                 -- 1 = main diagnosis
    PRIMARY KEY (encounter_key, diagnosis_key),
    FOREIGN KEY (encounter_key) REFERENCES fact_encounters(encounter_key),
    FOREIGN KEY (diagnosis_key) REFERENCES dim_diagnosis(diagnosis_key)
);

CREATE TABLE bridge_encounter_procedures (
    encounter_key      INT NOT NULL,
    procedure_key      INT NOT NULL,
    procedure_date_key INT,
    PRIMARY KEY (encounter_key, procedure_key),
    FOREIGN KEY (encounter_key)      REFERENCES fact_encounters(encounter_key),
    FOREIGN KEY (procedure_key)      REFERENCES dim_procedure(procedure_key),
    FOREIGN KEY (procedure_date_key) REFERENCES dim_date(date_key)
);

-- Check: list all the new tables
SHOW TABLES;
