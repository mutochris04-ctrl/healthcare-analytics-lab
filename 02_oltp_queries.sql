-- ============================================
-- STEP 1: The 4 business questions on the ORIGINAL database (OLTP)
-- Run each query alone (put the cursor in it and press Ctrl + Enter),
-- then read the time in the "Duration" column of the Output panel.
-- The results and times go into query_analysis.txt
-- ============================================

USE healthcare_oltp;

-- ============================================
-- QUESTION 1: Monthly encounters by specialty
-- For each month, specialty and encounter type:
-- how many encounters, and how many different patients?
-- Join chain: encounters -> providers -> specialties
-- ============================================
SELECT
    DATE_FORMAT(encounters.encounter_date, '%Y-%m') AS encounter_month,
    specialties.specialty_name,
    encounters.encounter_type,
    COUNT(*) AS total_encounters,
    COUNT(DISTINCT encounters.patient_id) AS unique_patients
FROM encounters
JOIN providers   ON encounters.provider_id = providers.provider_id
JOIN specialties ON providers.specialty_id = specialties.specialty_id
GROUP BY encounter_month, specialties.specialty_name, encounters.encounter_type
ORDER BY encounter_month, specialties.specialty_name, encounters.encounter_type;

-- ============================================
-- QUESTION 2: Top diagnosis-procedure pairs
-- Which diagnosis + procedure appear together most often
-- in the same encounter?
-- Diagnoses and procedures are in 2 separate junction tables,
-- joined on encounter_id. Every diagnosis of an encounter is
-- paired with every procedure of it -> many more rows (row explosion).
-- ============================================
SELECT
    diagnoses.icd10_code,
    diagnoses.icd10_description,
    procedures.cpt_code,
    procedures.cpt_description,
    COUNT(DISTINCT encounter_diagnoses.encounter_id) AS encounter_count
FROM encounter_diagnoses
JOIN encounter_procedures ON encounter_diagnoses.encounter_id = encounter_procedures.encounter_id
JOIN diagnoses            ON encounter_diagnoses.diagnosis_id = diagnoses.diagnosis_id
JOIN procedures           ON encounter_procedures.procedure_id = procedures.procedure_id
GROUP BY diagnoses.icd10_code, diagnoses.icd10_description,
         procedures.cpt_code, procedures.cpt_description
ORDER BY encounter_count DESC
LIMIT 10;

-- ============================================
-- QUESTION 3: 30-day readmission rate by specialty
-- A readmission = a patient is discharged from an INPATIENT stay
-- and is admitted again as an INPATIENT within 30 days.
-- I join the encounters table to ITSELF (self-join):
--   first_stay = the inpatient stay
--   next_stay  = a later inpatient stay of the same patient
-- LEFT JOIN keeps stays with no readmission (next_stay is NULL).
-- ============================================
SELECT
    specialties.specialty_name,
    COUNT(DISTINCT first_stay.encounter_id) AS inpatient_stays,
    COUNT(DISTINCT CASE WHEN next_stay.encounter_id IS NOT NULL
                        THEN first_stay.encounter_id END) AS readmitted_stays,
    ROUND(100 * COUNT(DISTINCT CASE WHEN next_stay.encounter_id IS NOT NULL
                                    THEN first_stay.encounter_id END)
              / COUNT(DISTINCT first_stay.encounter_id), 2) AS readmission_rate_percent
FROM encounters AS first_stay
JOIN providers   ON first_stay.provider_id = providers.provider_id
JOIN specialties ON providers.specialty_id = specialties.specialty_id
LEFT JOIN encounters AS next_stay
       ON  next_stay.patient_id = first_stay.patient_id
       AND next_stay.encounter_type = 'Inpatient'
       AND next_stay.encounter_date > first_stay.discharge_date
       AND next_stay.encounter_date <= DATE_ADD(first_stay.discharge_date, INTERVAL 30 DAY)
WHERE first_stay.encounter_type = 'Inpatient'
GROUP BY specialties.specialty_name
ORDER BY readmission_rate_percent DESC;

-- ============================================
-- QUESTION 4: Revenue by specialty and month
-- Total allowed amount (money the insurer agreed to pay).
-- Join chain: billing -> encounters -> providers -> specialties
-- Month = month of the encounter
-- ============================================
SELECT
    specialties.specialty_name,
    DATE_FORMAT(encounters.encounter_date, '%Y-%m') AS encounter_month,
    SUM(billing.allowed_amount) AS total_allowed
FROM billing
JOIN encounters  ON billing.encounter_id = encounters.encounter_id
JOIN providers   ON encounters.provider_id = providers.provider_id
JOIN specialties ON providers.specialty_id = specialties.specialty_id
GROUP BY specialties.specialty_name, encounter_month
ORDER BY specialties.specialty_name, encounter_month;

-- Extra: which specialty brings the most money in total?
SELECT
    specialties.specialty_name,
    SUM(billing.allowed_amount) AS total_allowed
FROM billing
JOIN encounters  ON billing.encounter_id = encounters.encounter_id
JOIN providers   ON encounters.provider_id = providers.provider_id
JOIN specialties ON providers.specialty_id = specialties.specialty_id
GROUP BY specialties.specialty_name
ORDER BY total_allowed DESC;
