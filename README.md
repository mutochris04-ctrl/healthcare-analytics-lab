# Healthcare Analytics Lab: OLTP to Star Schema

*DRAFT version*

A hospital database built for daily work (OLTP, normalized) answers analytics questions slowly. In this lab I measure 4 business questions on it, then design and build a **star schema** for analytics, move the data into it with an **ETL**, and compare the speed of the same questions.

I added a **Clinical Nutrition** service to the data (dietitians, malnutrition diagnoses, children as patients), keeping the tables exactly as in the instructions.

**Tools:** MySQL 8, MySQL Workbench, Python 3 (only to create the made-up data)
**Databases:** `healthcare_oltp` (original) and `healthcare_star` (star schema)

---

## Project Structure

```text
healthcare-analytics-lab/
│
│  Files I run, in this order:
├── 00_oltp_schema.sql          Step 0: original database, sample data + nutrition reference data
├── 01_oltp_generated_data.sql  Step 0: 5,000 patients and 30,000 encounters (made by generate_data.py)
├── 02_oltp_queries.sql         Step 1: the 4 questions on the original database
├── star_schema.sql             Step 3: the star schema tables, empty (name kept from the instructions)
├── 03_etl_load.sql             Step 4: fills the star schema from the original database
├── 04_star_queries.sql         Step 5: the 4 questions on the star schema (+ nutrition bonus)
│
│  Deliverable documents (names from the instructions):
├── query_analysis.txt          Step 1: queries, times and bottlenecks
├── design_decisions.txt        Step 2: grain, dimensions, metrics, bridge tables
├── etl_design.txt              Step 4: the ETL explained, refresh strategy
├── star_schema_queries.txt     Step 5: queries, times and improvement
├── reflection.md               Step 6: why it is faster, trade-offs, results
│
│  Other:
├── generate_data.py            creates 01_oltp_generated_data.sql
└── README.md
```

## How to Run

In MySQL Workbench, run these files in this order:

1. `00_oltp_schema.sql`: creates `healthcare_oltp` with the sample data
2. `01_oltp_generated_data.sql`: adds the made-up data. The file is big, so use **File → Run SQL Script** instead of opening it.
3. `02_oltp_queries.sql`: run each question alone (Ctrl + Enter) and note the Duration
4. `star_schema.sql`: creates the empty `healthcare_star`
5. `03_etl_load.sql`: fills the star schema. The last result checks that the counts and money match.
6. `04_star_queries.sql`: run each question alone and compare the Duration

To create new made-up data: `python generate_data.py` (always the same data, because of `random.seed(42)`).

## Star Schema

- **Fact table:** `fact_encounters`, one row per encounter, with keys to every dimension and pre-calculated metrics (diagnosis and procedure counts, claim and allowed totals, length of stay, 30-day readmission flag)
- **Dimensions:** `dim_date`, `dim_patient` (with age group), `dim_provider`, `dim_specialty`, `dim_department`, `dim_encounter_type`, `dim_diagnosis`, `dim_procedure`
- **Bridge tables:** `bridge_encounter_diagnoses`, `bridge_encounter_procedures` (an encounter has many diagnoses and procedures)

## Results (draft test run, 30,004 encounters)

| Question | Original | Star schema | Improvement |
|---|---|---|---|
| 1. Encounters by specialty | 75 ms | 110 ms | 0.7× (not faster) |
| 2. Diagnosis-procedure pairs | 445 ms | 124 ms | 3.6× faster |
| 3. 30-day readmission rate | 99 ms | 14 ms | 6.9× faster |
| 4. Revenue by specialty and month | 97 ms | 71 ms | 1.4× faster |

All results are identical in both databases. The reasons, including why Question 1 is not faster, are in `reflection.md`.

The data is made up, so the results show that the design works, not real facts about patients.

---

## Author

Christine Umutoni, AmaliTech Data Engineering training
