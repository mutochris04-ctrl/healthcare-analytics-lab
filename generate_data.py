# ============================================
# Create made-up (synthetic) hospital data
#
# Why: the sample data has only 4 encounters, so every query takes
# 0 seconds and we cannot see any "slowness".
# This program writes 01_oltp_generated_data.sql with thousands of
# patients, encounters, diagnoses, procedures and bills.
#
# How to run (in the VS Code terminal):  python generate_data.py
# Then run 01_oltp_generated_data.sql in MySQL Workbench
# (File -> Run SQL Script, because the file is big).
# ============================================

import random
from datetime import datetime, timedelta

# The same seed gives the same "random" data every time,
# so anyone can repeat my results.
random.seed(42)

NUMBER_OF_PATIENTS = 5000
NUMBER_OF_ENCOUNTERS = 30000


# ============================================
# 1. LISTS: values we can choose from
# ============================================
first_names_f = ["Aline", "Grace", "Diane", "Claudine", "Josiane", "Alice",
                 "Esther", "Ange", "Divine", "Sandrine", "Mary", "Sarah"]
first_names_m = ["Eric", "Patrick", "Jean", "David", "Emmanuel", "Olivier",
                 "Samuel", "Kevin", "Moses", "Fabrice", "John", "Robert"]
last_names = ["Uwase", "Mugisha", "Ingabire", "Habimana", "Niyonsaba",
              "Mukamana", "Nshimiyimana", "Uwimana", "Hakizimana", "Iradukunda",
              "Niyonzima", "Mutesi", "Smith", "Johnson", "Doe"]

# Providers by specialty (IDs from 00_oltp_schema.sql)
cardiology_providers = [101, 104]
internal_medicine_providers = [102, 105, 106]
emergency_providers = [103, 107]
nutrition_providers = [108, 109]

# Adults mostly see doctors; only one dietitian is in this list,
# so nutrition visits stay a smaller part of the hospital
all_adult_providers = (cardiology_providers + internal_medicine_providers
                       + emergency_providers + [108])

# The department of each provider
provider_department = {101: 1, 104: 1, 102: 2, 105: 2, 106: 2,
                       103: 3, 107: 3, 108: 4, 109: 4}

# Diagnoses (diagnosis_id) that fit each specialty
diagnoses_cardiology = [3001, 3003, 3005]          # hypertension, heart failure, chest pain
diagnoses_internal = [3001, 3002, 3004, 3009]      # hypertension, diabetes, pneumonia, anaemia
diagnoses_emergency = [3005, 3004, 3001]           # chest pain, pneumonia, hypertension
diagnoses_nutrition_adult = [3008, 3009, 3010, 3002]   # obesity, anaemia, vitamin D, diabetes
diagnoses_nutrition_child = [3006, 3007, 3009, 3010]   # severe/moderate malnutrition, anaemia, vitamin D

# Procedures (procedure_id) that fit each specialty
procedures_cardiology = [4001, 4002, 4003]   # office visit, EKG, chest X-ray
procedures_internal = [4001, 4004, 4003]     # office visit, blood count, chest X-ray
procedures_emergency = [4002, 4003, 4004]    # EKG, chest X-ray, blood count
procedures_nutrition = [4005, 4006, 4004]    # nutrition assessment, follow-up, blood count

# Visits happen in 2024 and 2025 (730 days)
VISITS_START = datetime(2024, 1, 1)
VISITS_DAYS = 730

# Every table gets its rows here, as dictionaries
patients = []
encounters = []
encounter_diagnoses = []
encounter_procedures = []
bills = []


# ============================================
# 2. SMALL HELPER FUNCTIONS
# ============================================
def random_date(start, number_of_days):
    """A random day within number_of_days after start, at a random time."""
    day = start + timedelta(days=random.randint(0, number_of_days - 1))
    return day.replace(hour=random.randint(7, 22), minute=random.choice([0, 15, 30, 45]))


def diagnoses_for(provider_id, is_child):
    """The list of diagnoses that fits the provider's specialty."""
    if provider_id in nutrition_providers:
        if is_child:
            return diagnoses_nutrition_child
        else:
            return diagnoses_nutrition_adult
    elif provider_id in cardiology_providers:
        return diagnoses_cardiology
    elif provider_id in emergency_providers:
        return diagnoses_emergency
    else:
        return diagnoses_internal


def procedures_for(provider_id):
    """The list of procedures that fits the provider's specialty."""
    if provider_id in nutrition_providers:
        return procedures_nutrition
    elif provider_id in cardiology_providers:
        return procedures_cardiology
    elif provider_id in emergency_providers:
        return procedures_emergency
    else:
        return procedures_internal


def choose_encounter_type(provider_id, is_child, diagnosis_ids):
    """Outpatient, Inpatient or ER, depending on the provider and diagnoses."""
    if provider_id in emergency_providers:
        return "ER"
    if is_child and 3006 in diagnosis_ids:     # severe malnutrition -> admitted
        return "Inpatient"
    if provider_id in nutrition_providers:
        if random.random() < 0.9:
            return "Outpatient"
        return "Inpatient"
    if random.random() < 0.75:
        return "Outpatient"
    return "Inpatient"


def discharge_after(encounter_date, encounter_type):
    """Outpatient: 30-120 minutes, ER: 2-10 hours, Inpatient: 1-8 days."""
    if encounter_type == "Outpatient":
        return encounter_date + timedelta(minutes=random.randint(30, 120))
    elif encounter_type == "ER":
        return encounter_date + timedelta(hours=random.randint(2, 10))
    else:
        return encounter_date + timedelta(days=random.randint(1, 8), hours=random.randint(0, 6))


def bill_amount(encounter_type):
    """A typical claim amount for each encounter type."""
    if encounter_type == "Outpatient":
        return random.randint(100, 500)
    elif encounter_type == "ER":
        return random.randint(800, 3000)
    else:
        return random.randint(5000, 20000)


# ============================================
# 3. FUNCTION: create one patient
# IDs start at 1004, after the 3 sample patients (1001-1003).
# About 20% are children, born July 2021 to June 2023, so during
# 2024-2025 they are 6 to 54 months old.
# ============================================
def create_patient(patient_id):
    gender = random.choice(["F", "M"])
    if gender == "F":
        first_name = random.choice(first_names_f)
    else:
        first_name = random.choice(first_names_m)
    last_name = random.choice(last_names)

    if random.random() < 0.2:
        is_child = True
        date_of_birth = random_date(datetime(2021, 7, 1), 730)
    else:
        is_child = False
        date_of_birth = random_date(datetime(1940, 1, 1), 22000)   # born 1940 to ~2000

    patient = {
        "patient_id": patient_id,
        "first_name": first_name,
        "last_name": last_name,
        "date_of_birth": date_of_birth.strftime("%Y-%m-%d"),
        "gender": gender,
        "mrn": f"MRN{patient_id}",
    }
    return patient, is_child


# ============================================
# 4. FUNCTION: create one visit, with its diagnoses,
# procedures and bill. New IDs continue after the sample data:
# encounters 7005+, diagnosis lines 8007+, procedure lines 9005+,
# bills 14003+  (next ID = first ID + rows already made)
# ============================================
def create_visit(patient_id, provider_id, is_child, encounter_date):
    encounter_id = 7005 + len(encounters)

    # 1 to 3 different diagnoses
    chosen_diagnoses = random.sample(diagnoses_for(provider_id, is_child), random.randint(1, 3))

    encounter_type = choose_encounter_type(provider_id, is_child, chosen_diagnoses)
    discharge_date = discharge_after(encounter_date, encounter_type)

    encounters.append({
        "encounter_id": encounter_id,
        "patient_id": patient_id,
        "provider_id": provider_id,
        "encounter_type": encounter_type,
        "encounter_date": encounter_date.strftime("%Y-%m-%d %H:%M:%S"),
        "discharge_date": discharge_date.strftime("%Y-%m-%d %H:%M:%S"),
        "department_id": provider_department[provider_id],
    })

    sequence = 1
    for diagnosis_id in chosen_diagnoses:
        encounter_diagnoses.append({
            "encounter_diagnosis_id": 8007 + len(encounter_diagnoses),
            "encounter_id": encounter_id,
            "diagnosis_id": diagnosis_id,
            "diagnosis_sequence": sequence,
        })
        sequence = sequence + 1

    # 1 or 2 different procedures, done on the visit day
    chosen_procedures = random.sample(procedures_for(provider_id), random.randint(1, 2))
    for procedure_id in chosen_procedures:
        encounter_procedures.append({
            "encounter_procedure_id": 9005 + len(encounter_procedures),
            "encounter_id": encounter_id,
            "procedure_id": procedure_id,
            "procedure_date": encounter_date.strftime("%Y-%m-%d"),
        })

    # The bill is sent 1 to 10 days after discharge
    claim = bill_amount(encounter_type)
    status = random.choices(["Paid", "Pending", "Denied"], weights=[80, 15, 5])[0]
    if status == "Denied":
        allowed = 0
    else:
        allowed = round(claim * random.uniform(0.7, 0.9), 2)
    claim_date = discharge_date + timedelta(days=random.randint(1, 10))

    bills.append({
        "billing_id": 14003 + len(bills),
        "encounter_id": encounter_id,
        "claim_amount": claim,
        "allowed_amount": allowed,
        "claim_date": claim_date.strftime("%Y-%m-%d"),
        "claim_status": status,
    })

    return encounter_type, discharge_date, chosen_diagnoses


# ============================================
# 5. FUNCTION: write a list of rows as INSERT statements,
# 500 rows per INSERT (much faster than one INSERT per row)
# ============================================
def to_sql_value(value):
    """Numbers stay as they are; text and dates get quotes."""
    if isinstance(value, str):
        return "'" + value + "'"
    return str(value)


def write_inserts(file, table_name, rows):
    for start in range(0, len(rows), 500):
        group = rows[start:start + 500]
        lines = []
        for row in group:
            values = []
            for value in row.values():
                values.append(to_sql_value(value))
            lines.append("(" + ", ".join(values) + ")")
        file.write(f"INSERT INTO {table_name} VALUES\n")
        file.write(",\n".join(lines))
        file.write(";\n\n")


# ============================================
# 6. FOR LOOP: create all the patients
# ============================================
children = []    # patient IDs of children
adults = []      # patient IDs of adults

for number in range(NUMBER_OF_PATIENTS):
    patient_id = 1004 + number
    patient, is_child = create_patient(patient_id)
    patients.append(patient)
    if is_child:
        children.append(patient_id)
    else:
        adults.append(patient_id)


# ============================================
# 7. WHILE LOOP: create visits until we have enough
# ============================================
while len(encounters) < NUMBER_OF_ENCOUNTERS:
    # Children only see the dietitians; adults can see anyone
    if random.random() < 0.08:
        patient_id = random.choice(children)
        is_child = True
        provider_id = random.choice(nutrition_providers)
    else:
        patient_id = random.choice(adults)
        is_child = False
        provider_id = random.choice(all_adult_providers)

    encounter_date = random_date(VISITS_START, VISITS_DAYS)
    encounter_type, discharge_date, diagnoses = create_visit(patient_id, provider_id,
                                                             is_child, encounter_date)

    # Nutrition story: some children with severe malnutrition (E43)
    # come back to hospital 5 to 25 days after discharge (readmission)
    if is_child and 3006 in diagnoses and random.random() < 0.3:
        return_date = discharge_date + timedelta(days=random.randint(5, 25))
        create_visit(patient_id, provider_id, is_child, return_date)


# ============================================
# 8. SAVE everything into one SQL file
# (order matters: patients and encounters BEFORE the rows that point to them)
# ============================================
with open("01_oltp_generated_data.sql", "w") as file:
    file.write("-- Made-up hospital data, created by generate_data.py\n")
    file.write("-- Run AFTER 00_oltp_schema.sql\n\n")
    file.write("USE healthcare_oltp;\n\n")
    write_inserts(file, "patients", patients)
    write_inserts(file, "encounters", encounters)
    write_inserts(file, "encounter_diagnoses", encounter_diagnoses)
    write_inserts(file, "encounter_procedures", encounter_procedures)
    write_inserts(file, "billing", bills)


# ============================================
# 9. DISPLAY RESULTS
# ============================================
print("Done! 01_oltp_generated_data.sql was created.")
print("Patients:", len(patients))
print("Encounters:", len(encounters))
print("Diagnosis lines:", len(encounter_diagnoses))
print("Procedure lines:", len(encounter_procedures))
print("Bills:", len(bills))
print("\nFirst 2 patients:")
for patient in patients[:2]:
    print(patient)
print("\nFirst 2 visits:")
for visit in encounters[:2]:
    print(visit)
