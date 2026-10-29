-- ============================================
-- STEP 5: The SAME 4 questions on the STAR SCHEMA
-- Run each query alone (cursor in it, Ctrl + Enter) and read
-- the Duration. Results must be the SAME as in 02_oltp_queries.sql,
-- only faster and simpler. Documented in star_schema_queries.txt
-- ============================================

USE healthcare_star;

-- ============================================
-- QUESTION 1: Monthly encounters by specialty
-- Before: encounters -> providers -> specialties + DATE_FORMAT on every row
-- Now: the fact table has specialty_key directly, and the month
-- is already in dim_date (year_and_month)
-- ============================================
SELECT
    dim_date.year_and_month AS encounter_month,
    dim_specialty.specialty_name,
    dim_encounter_type.encounter_type_name AS encounter_type,
    COUNT(*) AS total_encounters,
    COUNT(DISTINCT fact_encounters.patient_key) AS unique_patients
FROM fact_encounters
JOIN dim_date           ON fact_encounters.encounter_date_key = dim_date.date_key
JOIN dim_specialty      ON fact_encounters.specialty_key = dim_specialty.specialty_key
JOIN dim_encounter_type ON fact_encounters.encounter_type_key = dim_encounter_type.encounter_type_key
GROUP BY encounter_month, dim_specialty.specialty_name, encounter_type
ORDER BY encounter_month, dim_specialty.specialty_name, encounter_type;

-- ============================================
-- QUESTION 2: Top diagnosis-procedure pairs
-- Pairs ARE many-to-many, so I still use the 2 bridge tables.
-- Trick: first count the pairs using only the KEYS (small whole
-- numbers) in a subquery called "pairs", THEN look up the
-- 38 pair names. Names are joined 38 times, not 90,000 times.
-- ============================================
SELECT
    dim_diagnosis.icd10_code,
    dim_diagnosis.icd10_description,
    dim_procedure.cpt_code,
    dim_procedure.cpt_description,
    pairs.encounter_count
FROM (
    -- Step A: for every (diagnosis, procedure) pair of keys,
    -- count the DIFFERENT encounters that have it (same as the original)
    SELECT
        bridge_encounter_diagnoses.diagnosis_key,
        bridge_encounter_procedures.procedure_key,
        COUNT(DISTINCT bridge_encounter_diagnoses.encounter_key) AS encounter_count
    FROM bridge_encounter_diagnoses
    JOIN bridge_encounter_procedures
         ON bridge_encounter_diagnoses.encounter_key = bridge_encounter_procedures.encounter_key
    GROUP BY bridge_encounter_diagnoses.diagnosis_key, bridge_encounter_procedures.procedure_key
) AS pairs
-- Step B: add the codes and names
JOIN dim_diagnosis ON pairs.diagnosis_key = dim_diagnosis.diagnosis_key
JOIN dim_procedure ON pairs.procedure_key = dim_procedure.procedure_key
ORDER BY pairs.encounter_count DESC
LIMIT 10;

-- ============================================
-- QUESTION 3: 30-day readmission rate by specialty
-- Before: a self-join of encounters with date comparisons
-- Now: the ETL already set is_readmitted_30_days (1 or 0),
-- so SUM() counts the readmissions. No self-join.
-- ============================================
SELECT
    dim_specialty.specialty_name,
    COUNT(*) AS inpatient_stays,
    SUM(fact_encounters.is_readmitted_30_days) AS readmitted_stays,
    ROUND(100 * SUM(fact_encounters.is_readmitted_30_days) / COUNT(*), 2) AS readmission_rate_percent
FROM fact_encounters
JOIN dim_specialty      ON fact_encounters.specialty_key = dim_specialty.specialty_key
JOIN dim_encounter_type ON fact_encounters.encounter_type_key = dim_encounter_type.encounter_type_key
WHERE dim_encounter_type.encounter_type_name = 'Inpatient'
GROUP BY dim_specialty.specialty_name
ORDER BY readmission_rate_percent DESC;

-- ============================================
-- QUESTION 4: Revenue by specialty and month
-- Before: billing -> encounters -> providers -> specialties
-- Now: total_allowed_amount is already in the fact table
-- WHERE bill_count > 0: only encounters that have a bill,
-- exactly like the original query, which starts from billing
-- ============================================
SELECT
    dim_specialty.specialty_name,
    dim_date.year_and_month AS encounter_month,
    SUM(fact_encounters.total_allowed_amount) AS total_allowed
FROM fact_encounters
JOIN dim_specialty ON fact_encounters.specialty_key = dim_specialty.specialty_key
JOIN dim_date      ON fact_encounters.encounter_date_key = dim_date.date_key
WHERE fact_encounters.bill_count > 0
GROUP BY dim_specialty.specialty_name, encounter_month
ORDER BY dim_specialty.specialty_name, encounter_month;

-- Extra: which specialty brings the most money in total?
SELECT
    dim_specialty.specialty_name,
    SUM(fact_encounters.total_allowed_amount) AS total_allowed
FROM fact_encounters
JOIN dim_specialty ON fact_encounters.specialty_key = dim_specialty.specialty_key
WHERE fact_encounters.bill_count > 0
GROUP BY dim_specialty.specialty_name
ORDER BY total_allowed DESC;

-- ============================================
-- BONUS (nutrition): readmission rate by age group,
-- for Clinical Nutrition stays. Easy in a star schema:
-- just one more dimension in the query.
-- Note: age_group = age on 31 Dec 2025 (fixed date in the ETL),
-- not always the age on the day of the stay.
-- ============================================
SELECT
    dim_patient.age_group,
    COUNT(*) AS inpatient_stays,
    SUM(fact_encounters.is_readmitted_30_days) AS readmitted_stays,
    ROUND(100 * SUM(fact_encounters.is_readmitted_30_days) / COUNT(*), 2) AS readmission_rate_percent
FROM fact_encounters
JOIN dim_patient        ON fact_encounters.patient_key = dim_patient.patient_key
JOIN dim_specialty      ON fact_encounters.specialty_key = dim_specialty.specialty_key
JOIN dim_encounter_type ON fact_encounters.encounter_type_key = dim_encounter_type.encounter_type_key
WHERE dim_encounter_type.encounter_type_name = 'Inpatient'
  AND dim_specialty.specialty_name = 'Clinical Nutrition'
GROUP BY dim_patient.age_group
ORDER BY readmission_rate_percent DESC;
