-- ============================================
-- STEP 0: The original hospital database (OLTP)
-- OLTP = the database the hospital uses every day to RECORD things
-- (a patient registers, a doctor sees them, a bill is sent).
-- The data is split into 10 small tables (normalized, 3NF),
-- exactly as given in the lab instructions (Part 1).
--
-- At the end I add EXTRA reference data for a Clinical Nutrition
-- service (my nutrition background). The tables stay the same.
--
-- Run this file first. It deletes and rebuilds the database,
-- so it is safe to run again.
-- ============================================

DROP DATABASE IF EXISTS healthcare_oltp;
CREATE DATABASE healthcare_oltp;
USE healthcare_oltp;

-- ============================================
-- Tables (from the lab instructions)
-- ============================================

CREATE TABLE patients (
    patient_id INT PRIMARY KEY,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    date_of_birth DATE,
    gender CHAR(1),
    mrn VARCHAR(20) UNIQUE          -- medical record number
);

CREATE TABLE specialties (
    specialty_id INT PRIMARY KEY,
    specialty_name VARCHAR(100),
    specialty_code VARCHAR(10)
);

CREATE TABLE departments (
    department_id INT PRIMARY KEY,
    department_name VARCHAR(100),
    floor INT,
    capacity INT
);

CREATE TABLE providers (
    provider_id INT PRIMARY KEY,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    credential VARCHAR(20),
    specialty_id INT,
    department_id INT,
    FOREIGN KEY (specialty_id) REFERENCES specialties(specialty_id),
    FOREIGN KEY (department_id) REFERENCES departments(department_id)
);

CREATE TABLE encounters (
    encounter_id INT PRIMARY KEY,
    patient_id INT,
    provider_id INT,
    encounter_type VARCHAR(50), -- 'Outpatient', 'Inpatient', 'ER'
    encounter_date DATETIME,
    discharge_date DATETIME,
    department_id INT,
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id),
    FOREIGN KEY (provider_id) REFERENCES providers(provider_id),
    FOREIGN KEY (department_id) REFERENCES departments(department_id),
    INDEX idx_encounter_date (encounter_date)
);

CREATE TABLE diagnoses (
    diagnosis_id INT PRIMARY KEY,
    icd10_code VARCHAR(10),
    icd10_description VARCHAR(200)
);

CREATE TABLE encounter_diagnoses (
    encounter_diagnosis_id INT PRIMARY KEY,
    encounter_id INT,
    diagnosis_id INT,
    diagnosis_sequence INT,
    FOREIGN KEY (encounter_id) REFERENCES encounters(encounter_id),
    FOREIGN KEY (diagnosis_id) REFERENCES diagnoses(diagnosis_id)
);

CREATE TABLE procedures (
    procedure_id INT PRIMARY KEY,
    cpt_code VARCHAR(10),
    cpt_description VARCHAR(200)
);

CREATE TABLE encounter_procedures (
    encounter_procedure_id INT PRIMARY KEY,
    encounter_id INT,
    procedure_id INT,
    procedure_date DATE,
    FOREIGN KEY (encounter_id) REFERENCES encounters(encounter_id),
    FOREIGN KEY (procedure_id) REFERENCES procedures(procedure_id)
);

CREATE TABLE billing (
    billing_id INT PRIMARY KEY,
    encounter_id INT,
    claim_amount DECIMAL(12, 2),
    allowed_amount DECIMAL(12, 2),
    claim_date DATE,
    claim_status VARCHAR(50),
    FOREIGN KEY (encounter_id) REFERENCES encounters(encounter_id),
    INDEX idx_claim_date (claim_date)
);

-- ============================================
-- Sample data (from the lab instructions)
-- Note: encounters must be inserted BEFORE billing,
-- because billing points to encounters (foreign key).
-- ============================================

INSERT INTO specialties VALUES
    (1, 'Cardiology', 'CARD'),
    (2, 'Internal Medicine', 'IM'),
    (3, 'Emergency', 'ER');

INSERT INTO departments VALUES
    (1, 'Cardiology Unit', 3, 20),
    (2, 'Internal Medicine', 2, 30),
    (3, 'Emergency', 1, 45);

INSERT INTO providers VALUES
    (101, 'James', 'Chen', 'MD', 1, 1),
    (102, 'Sarah', 'Williams', 'MD', 2, 2),
    (103, 'Michael', 'Rodriguez', 'MD', 3, 3);

INSERT INTO patients VALUES
    (1001, 'John', 'Doe', '1955-03-15', 'M', 'MRN001'),
    (1002, 'Jane', 'Smith', '1962-07-22', 'F', 'MRN002'),
    (1003, 'Robert', 'Johnson', '1948-11-08', 'M', 'MRN003');

INSERT INTO diagnoses VALUES
    (3001, 'I10', 'Hypertension'),
    (3002, 'E11.9', 'Type 2 Diabetes'),
    (3003, 'I50.9', 'Heart Failure');

INSERT INTO procedures VALUES
    (4001, '99213', 'Office Visit'),
    (4002, '93000', 'EKG'),
    (4003, '71020', 'Chest X-ray');

INSERT INTO encounters VALUES
    (7001, 1001, 101, 'Outpatient', '2024-05-10 10:00:00', '2024-05-10 11:30:00', 1),
    (7002, 1001, 101, 'Inpatient', '2024-06-02 14:00:00', '2024-06-06 09:00:00', 1),
    (7003, 1002, 102, 'Outpatient', '2024-05-15 09:00:00', '2024-05-15 10:15:00', 2),
    (7004, 1003, 103, 'ER', '2024-06-12 23:45:00', '2024-06-13 06:30:00', 3);

INSERT INTO billing VALUES
    (14001, 7001, 350, 280, '2024-05-11', 'Paid'),
    (14002, 7002, 12500, 10000, '2024-06-08', 'Paid');

INSERT INTO encounter_diagnoses VALUES
    (8001, 7001, 3001, 1), (8002, 7001, 3002, 2),
    (8003, 7002, 3001, 1), (8004, 7002, 3003, 2),
    (8005, 7003, 3002, 1), (8006, 7004, 3001, 1);

INSERT INTO encounter_procedures VALUES
    (9001, 7001, 4001, '2024-05-10'), (9002, 7001, 4002, '2024-05-10'),
    (9003, 7002, 4001, '2024-06-02'), (9004, 7003, 4001, '2024-05-15');

-- ============================================
-- EXTRA reference data: Clinical Nutrition service (my addition)
-- Same tables, only more rows.
-- ============================================

-- A 4th specialty and department for nutrition
INSERT INTO specialties VALUES
    (4, 'Clinical Nutrition', 'NUTR');

INSERT INTO departments VALUES
    (4, 'Nutrition Unit', 2, 15);

-- More providers, so the data looks like a real hospital.
-- RD = Registered Dietitian
INSERT INTO providers VALUES
    (104, 'Aline', 'Uwase', 'MD', 1, 1),
    (105, 'Eric', 'Mugisha', 'MD', 2, 2),
    (106, 'Grace', 'Ingabire', 'MD', 2, 2),
    (107, 'Patrick', 'Habimana', 'MD', 3, 3),
    (108, 'Diane', 'Mukamana', 'RD', 4, 4),
    (109, 'Claude', 'Niyonsaba', 'RD', 4, 4);

-- More diagnoses: general ones + nutrition ones (real ICD-10 codes)
INSERT INTO diagnoses VALUES
    (3004, 'J18.9', 'Pneumonia'),
    (3005, 'R07.9', 'Chest Pain'),
    (3006, 'E43',   'Severe Protein-Calorie Malnutrition'),
    (3007, 'E44.0', 'Moderate Protein-Calorie Malnutrition'),
    (3008, 'E66.9', 'Obesity'),
    (3009, 'D50.9', 'Iron Deficiency Anaemia'),
    (3010, 'E55.9', 'Vitamin D Deficiency');

-- More procedures: general ones + nutrition ones (real CPT codes)
INSERT INTO procedures VALUES
    (4004, '85025', 'Complete Blood Count'),
    (4005, '97802', 'Medical Nutrition Therapy - First Assessment'),
    (4006, '97803', 'Medical Nutrition Therapy - Follow-up');

-- Check: count the rows in each table
SELECT 'specialties' AS table_name, COUNT(*) AS number_of_rows FROM specialties
UNION ALL SELECT 'departments', COUNT(*) FROM departments
UNION ALL SELECT 'providers', COUNT(*) FROM providers
UNION ALL SELECT 'patients', COUNT(*) FROM patients
UNION ALL SELECT 'diagnoses', COUNT(*) FROM diagnoses
UNION ALL SELECT 'procedures', COUNT(*) FROM procedures
UNION ALL SELECT 'encounters', COUNT(*) FROM encounters;
