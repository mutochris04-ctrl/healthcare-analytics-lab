# Healthcare Analytics Lab: OLTP to Star Schema

A hospital database built for daily work (OLTP, normalized) answers analytics questions slowly. In this lab I measure 4 business questions on it, then design and build a **star schema** for analytics, move the data into it with an **ETL**, and compare the speed of the same questions.

I added a **Clinical Nutrition** service to the data (dietitians, malnutrition diagnoses, children as patients), keeping the tables exactly as in the instructions.

**Tools:** MySQL 8, MySQL Workbench, Python 3 (only to create the made-up data)
**Databases:** `healthcare_oltp` (original) and `healthcare_star` (star schema)

---

## Project Structure

```text
healthcare-analytics-lab/
├── README.md                       this guide
├── reflection.md                   Step 6: why it is faster, trade-offs, results
├── generate_data.py                creates sql/01_oltp_generated_data.sql (made-up data)
│
├── sql/                            everything I RUN, in this order:
│   ├── 00_oltp_schema.sql          Step 0: original database, sample data + nutrition reference data
│   ├── 01_oltp_generated_data.sql  Step 0: 5,000 patients and 30,000 encounters
│   ├── 02_oltp_queries.sql         Step 1: the 4 questions on the original database
│   ├── star_schema.sql             Step 3: the star schema tables, empty (name kept from the instructions)
│   ├── 03_etl_load.sql             Step 4: fills the star schema and checks it (8 checks)
│   └── 04_star_queries.sql         Step 5: the 4 questions on the star schema (+ nutrition bonus)
│
└── analysis/                       the written analysis (names from the instructions):
    ├── query_analysis.txt          Step 1: queries, times and bottlenecks
    ├── design_decisions.txt        Step 2: grain, dimensions, metrics, bridge tables
    ├── etl_design.txt              Step 4: the ETL explained, checks, refresh strategy
    └── star_schema_queries.txt     Step 5: queries, times and improvement
```

## How to Run

In MySQL Workbench, run these files from the `sql/` folder, in this order:

1. `00_oltp_schema.sql`: creates `healthcare_oltp` with the sample data
2. `01_oltp_generated_data.sql`: adds the made-up data. The file is big, so use **File → Run SQL Script** instead of opening it.
3. `02_oltp_queries.sql`: run each question alone (Ctrl + Enter) and note the Duration
4. `star_schema.sql`: creates the empty `healthcare_star`
5. `03_etl_load.sql`: fills the star schema. The last result checks that the counts, money and readmissions match (8 rows).
6. `04_star_queries.sql`: run each question alone and compare the Duration

To load the star schema again, always run `star_schema.sql` first (it empties everything), then `03_etl_load.sql`.

To create new made-up data, in a terminal in the main project folder: `python generate_data.py` (always the same data, because of `random.seed(42)`).

## Star Schema

- **Fact table:** `fact_encounters`, one row per encounter, with keys to every dimension and pre-calculated metrics (diagnosis, procedure and bill counts, claim and allowed totals, length of stay, 30-day readmission flag)
- **Dimensions:** `dim_date`, `dim_patient` (with age group), `dim_provider`, `dim_specialty`, `dim_department`, `dim_encounter_type`, `dim_diagnosis`, `dim_procedure`
- **Bridge tables:** `bridge_encounter_diagnoses`, `bridge_encounter_procedures` (an encounter has many diagnoses and procedures)

## Results (MySQL Workbench, 3 runs per query, middle value, 30,004 encounters)

| Question | Original | Star schema | Improvement |
|---|---|---|---|
| 1. Encounters by specialty | 0.094 s | 0.141 s | not faster |
| 2. Diagnosis-procedure pairs | 0.703 s | 0.156 s | about 4.5× faster |
| 3. 30-day readmission rate | 0.125 s | 0.016 s | about 8× faster |
| 4. Revenue by specialty and month | 0.188 s | 0.094 s | about 2× faster |

All results are identical in both databases, and the ETL checks (8 rows) prove the counts, money and readmissions match. The reasons, including why Question 1 is not faster, are in `reflection.md`, and the details per question in `analysis/`.

The data is made up, so the results show that the design works, not real facts about patients.

---

## Author

Christine Umutoni, AmaliTech Data Engineering training
