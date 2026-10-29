-- ============================================
-- STEP 4: ETL = Extract, Transform, Load
--   Extract   : read the data from the original database (healthcare_oltp)
--   Transform : change it into the shape of the star schema
--               (new keys, age groups, counts, totals, readmission flag)
--   Load      : insert it into the star schema (healthcare_star)
--
-- Order matters: dimensions FIRST, then the fact table,
-- then the bridge tables (they need the keys made before them).
--
-- Run AFTER 00_oltp_schema.sql, 01_oltp_generated_data.sql and star_schema.sql.
-- To load again, run star_schema.sql first (it empties everything).
-- ============================================

USE healthcare_star;

-- ============================================
-- 1. dim_date: one row for every day from 2023 to 2026
-- A small procedure with a WHILE loop (like a while loop in Python):
-- start at the first day, add 1 day each time, stop after the last day.
-- ============================================
DROP PROCEDURE IF EXISTS load_dim_date;

DELIMITER $$

CREATE PROCEDURE load_dim_date(IN p_start DATE, IN p_end DATE)
BEGIN
    DECLARE v_day DATE;
    SET v_day = p_start;

    WHILE v_day <= p_end DO
        INSERT INTO dim_date (date_key, calendar_date, year, quarter, month, month_name,
                              year_and_month, day_of_month, day_name, is_weekend)
        VALUES (
            YEAR(v_day) * 10000 + MONTH(v_day) * 100 + DAY(v_day),   -- 2024-05-10 -> 20240510
            v_day,
            YEAR(v_day),
            QUARTER(v_day),
            MONTH(v_day),
            MONTHNAME(v_day),
            DATE_FORMAT(v_day, '%Y-%m'),
            DAY(v_day),
            DAYNAME(v_day),
            CASE WHEN DAYOFWEEK(v_day) IN (1, 7) THEN 1 ELSE 0 END    -- 1 = Sunday, 7 = Saturday
        );
        SET v_day = DATE_ADD(v_day, INTERVAL 1 DAY);
    END WHILE;
END$$

DELIMITER ;

CALL load_dim_date('2023-01-01', '2026-12-31');

-- ============================================
-- 2. Small dimensions: copy the rows, MySQL makes the new keys
-- ============================================
INSERT INTO dim_specialty (specialty_id, specialty_name, specialty_code)
SELECT specialty_id, specialty_name, specialty_code
FROM healthcare_oltp.specialties;

INSERT INTO dim_department (department_id, department_name, floor, capacity)
SELECT department_id, department_name, floor, capacity
FROM healthcare_oltp.departments;

INSERT INTO dim_diagnosis (diagnosis_id, icd10_code, icd10_description)
SELECT diagnosis_id, icd10_code, icd10_description
FROM healthcare_oltp.diagnoses;

INSERT INTO dim_procedure (procedure_id, cpt_code, cpt_description)
SELECT procedure_id, cpt_code, cpt_description
FROM healthcare_oltp.procedures;

-- Encounter types: the different values found in encounters
INSERT INTO dim_encounter_type (encounter_type_name)
SELECT DISTINCT encounter_type
FROM healthcare_oltp.encounters;

-- ============================================
-- 3. dim_provider: DENORMALIZE = copy the specialty and
-- department names into the provider row (JOIN once, here)
-- ============================================
INSERT INTO dim_provider (provider_id, provider_name, credential, specialty_name, department_name)
SELECT
    providers.provider_id,
    CONCAT(providers.first_name, ' ', providers.last_name),
    providers.credential,
    specialties.specialty_name,
    departments.department_name
FROM healthcare_oltp.providers
JOIN healthcare_oltp.specialties ON providers.specialty_id = specialties.specialty_id
JOIN healthcare_oltp.departments ON providers.department_id = departments.department_id;

-- ============================================
-- 4. dim_patient: calculate an age group
-- Age = age on 31 Dec 2025 (the end of my data), so it does not
-- change every time the load is run.
-- ============================================
INSERT INTO dim_patient (patient_id, first_name, last_name, gender, date_of_birth, age_group, mrn)
SELECT
    patient_id,
    first_name,
    last_name,
    gender,
    date_of_birth,
    CASE
        WHEN TIMESTAMPDIFF(YEAR, date_of_birth, '2025-12-31') < 5  THEN '0-4 (child)'
        WHEN TIMESTAMPDIFF(YEAR, date_of_birth, '2025-12-31') < 18 THEN '5-17'
        WHEN TIMESTAMPDIFF(YEAR, date_of_birth, '2025-12-31') < 40 THEN '18-39'
        WHEN TIMESTAMPDIFF(YEAR, date_of_birth, '2025-12-31') < 65 THEN '40-64'
        ELSE '65+'
    END,
    mrn
FROM healthcare_oltp.patients;

-- ============================================
-- 5. fact_encounters: one row per encounter
--   - look up the new keys by JOINing each dimension on its old ID
--   - count diagnoses and procedures, add up the bills (pre-aggregation)
--   - set the readmission flag once, here
-- IFNULL(..., 0): an encounter without a bill gets 0, not NULL
-- ============================================
INSERT INTO fact_encounters (
    encounter_id, encounter_date_key, discharge_date_key,
    patient_key, provider_key, specialty_key, department_key, encounter_type_key,
    encounter_datetime, discharge_datetime,
    diagnosis_count, procedure_count, total_claim_amount, total_allowed_amount,
    length_of_stay_hours, is_readmitted_30_days
)
SELECT
    encounters.encounter_id,

    -- date keys: 2024-05-10 10:00 -> 20240510
    YEAR(encounters.encounter_date) * 10000 + MONTH(encounters.encounter_date) * 100
        + DAY(encounters.encounter_date),
    YEAR(encounters.discharge_date) * 10000 + MONTH(encounters.discharge_date) * 100
        + DAY(encounters.discharge_date),

    dim_patient.patient_key,
    dim_provider.provider_key,
    dim_specialty.specialty_key,
    dim_department.department_key,
    dim_encounter_type.encounter_type_key,

    encounters.encounter_date,
    encounters.discharge_date,

    -- how many diagnoses for this encounter
    (SELECT COUNT(*) FROM healthcare_oltp.encounter_diagnoses
     WHERE encounter_diagnoses.encounter_id = encounters.encounter_id),

    -- how many procedures for this encounter
    (SELECT COUNT(*) FROM healthcare_oltp.encounter_procedures
     WHERE encounter_procedures.encounter_id = encounters.encounter_id),

    -- money asked and money accepted for this encounter
    IFNULL((SELECT SUM(claim_amount) FROM healthcare_oltp.billing
            WHERE billing.encounter_id = encounters.encounter_id), 0),
    IFNULL((SELECT SUM(allowed_amount) FROM healthcare_oltp.billing
            WHERE billing.encounter_id = encounters.encounter_id), 0),

    -- length of stay in hours
    TIMESTAMPDIFF(HOUR, encounters.encounter_date, encounters.discharge_date),

    -- readmission flag: 1 if this is an inpatient stay AND the same patient
    -- has another inpatient stay that starts within 30 days after discharge
    CASE
        WHEN encounters.encounter_type = 'Inpatient' AND EXISTS (
            SELECT 1
            FROM healthcare_oltp.encounters AS next_stay
            WHERE next_stay.patient_id = encounters.patient_id
              AND next_stay.encounter_type = 'Inpatient'
              AND next_stay.encounter_date > encounters.discharge_date
              AND next_stay.encounter_date <= DATE_ADD(encounters.discharge_date, INTERVAL 30 DAY)
        ) THEN 1
        ELSE 0
    END

FROM healthcare_oltp.encounters
JOIN healthcare_oltp.providers ON encounters.provider_id = providers.provider_id
JOIN dim_patient        ON dim_patient.patient_id = encounters.patient_id
JOIN dim_provider       ON dim_provider.provider_id = encounters.provider_id
JOIN dim_specialty      ON dim_specialty.specialty_id = providers.specialty_id
JOIN dim_department     ON dim_department.department_id = encounters.department_id
JOIN dim_encounter_type ON dim_encounter_type.encounter_type_name = encounters.encounter_type;

-- ============================================
-- 6. Bridge tables: link each encounter to its diagnoses and procedures,
-- using the NEW keys
-- ============================================
INSERT INTO bridge_encounter_diagnoses (encounter_key, diagnosis_key, diagnosis_sequence)
SELECT
    fact_encounters.encounter_key,
    dim_diagnosis.diagnosis_key,
    encounter_diagnoses.diagnosis_sequence
FROM healthcare_oltp.encounter_diagnoses
JOIN fact_encounters ON fact_encounters.encounter_id = encounter_diagnoses.encounter_id
JOIN dim_diagnosis   ON dim_diagnosis.diagnosis_id = encounter_diagnoses.diagnosis_id;

INSERT INTO bridge_encounter_procedures (encounter_key, procedure_key, procedure_date_key)
SELECT
    fact_encounters.encounter_key,
    dim_procedure.procedure_key,
    YEAR(encounter_procedures.procedure_date) * 10000 + MONTH(encounter_procedures.procedure_date) * 100
        + DAY(encounter_procedures.procedure_date)
FROM healthcare_oltp.encounter_procedures
JOIN fact_encounters ON fact_encounters.encounter_id = encounter_procedures.encounter_id
JOIN dim_procedure   ON dim_procedure.procedure_id = encounter_procedures.procedure_id;

-- ============================================
-- 7. Checks: the star schema must have the SAME number of
-- encounters, diagnosis lines and procedure lines as the original
-- ============================================
SELECT 'encounters' AS what,
       (SELECT COUNT(*) FROM healthcare_oltp.encounters) AS in_original,
       (SELECT COUNT(*) FROM fact_encounters)            AS in_star_schema
UNION ALL
SELECT 'diagnosis lines',
       (SELECT COUNT(*) FROM healthcare_oltp.encounter_diagnoses),
       (SELECT COUNT(*) FROM bridge_encounter_diagnoses)
UNION ALL
SELECT 'procedure lines',
       (SELECT COUNT(*) FROM healthcare_oltp.encounter_procedures),
       (SELECT COUNT(*) FROM bridge_encounter_procedures)
UNION ALL
SELECT 'total allowed amount',
       (SELECT SUM(allowed_amount) FROM healthcare_oltp.billing),
       (SELECT SUM(total_allowed_amount) FROM fact_encounters);
