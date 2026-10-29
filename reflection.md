# Reflection: OLTP vs Star Schema

*Draft. Times come from 3 test runs on a test machine (30,004 encounters, MySQL 8); they will be re-measured in MySQL Workbench for the final version.*

## 1. Why is the star schema faster?

**Fewer joins to reach the answer.** In the original database, the specialty is not on the encounter, so every question has to follow a chain: billing → encounters → providers → specialties (3 joins for revenue). In the star schema, `specialty_key` and the money are on the fact row, so each question joins the fact table once to each dimension it needs.

| Question | Joins (original) | Joins (star) |
|---|---|---|
| 1. Encounters by specialty | 2 | 3 (date, specialty, type) |
| 2. Diagnosis-procedure pairs | 3 | 3 (2 bridges + 2 dimensions, after grouping) |
| 3. Readmission rate | 3, including a self-join | 2, no self-join |
| 4. Revenue by specialty and month | 3 | 2 |

**Data is pre-computed.** The ETL does the hard work once per load:
- the month, quarter and day names are stored in `dim_date`, so no `DATE_FORMAT()` on every row
- diagnosis and procedure counts and bill totals are stored on each fact row, so no join to `billing`
- the 30-day readmission check is done once and stored as `is_readmitted_30_days` (1 or 0), so the report is just a `SUM()` with no self-join

**Why denormalization helps analytics.** Normalized tables avoid repeating data, which is right when the hospital is recording visits all day. Analytics only reads data, many rows at once. Copying a few names and totals into the right place (for example the specialty name into `dim_provider`, the money into the fact table) means the database follows fewer links per row.

## 2. Trade-offs: what did I gain, what did I lose?

**Gained**
- Faster questions: readmission about 8–15× and diagnosis-procedure pairs about 3–4× faster
- Simpler SQL: the readmission question went from a self-join with date comparisons to one `SUM()`
- New questions are easy: adding "by age group" needed only one more JOIN (`dim_patient`)

**Lost**
- **Duplicated data:** names and totals exist in two databases, and the specialty name is in both `dim_specialty` and `dim_provider`. More storage.
- **ETL work:** a new process (`03_etl_load.sql`) that has to be written, run every night, checked and fixed when it fails.
- **Freshness:** the star schema is only as recent as the last load. A visit from this morning is not in the report until tonight.
- **Rules frozen at load time:** the readmission rule (30 days, inpatient only) is built into the data. If the hospital changes the rule, the ETL must be changed and the data reloaded.

**Was it worth it?** For the readmission and pair questions, yes. Questions 1 and 4 run at about the same speed with this amount of data (see section 4), but their SQL is simpler. For a hospital that runs these reports every day on years of data, yes, because the cost (one load per night) is paid once and the savings come with every report.

## 3. Bridge tables: worth it?

**Why keep diagnoses and procedures in bridge tables instead of the fact table?** One encounter has 1–3 diagnoses and 1–2 procedures. Putting them in the fact table would make it one row per diagnosis (or per procedure), so an encounter would be counted 2–3 times and its money added 2–3 times. Keeping one row per encounter keeps every `COUNT(*)` and `SUM()` correct, and the counts I need most (`diagnosis_count`, `procedure_count`) are still on the fact row.

**The trade-off.** Question 2 still has to join two bridge tables and still creates 89,951 pair rows: the many-to-many problem does not disappear. The bridges make it smaller and faster (keys only, primary key starting with `encounter_key`), but the main gain for Question 2 came from the query itself (count pairs of keys first, then add the names). On the original database, the same trick takes about 180 ms. So a large part of the gain comes from the better query, and the rest from the compact bridge tables.

**In production?** I would keep the bridge tables. If "top diagnosis-procedure pairs" became a daily report, I would add a small summary table with the pair counts per month, filled by the ETL, so the report would read about 38 rows instead of building 89,951 every time.

## 4. Performance quantification

I ran 3 test runs; in each run every query ran 5 times and I kept the median (MySQL profiling). The table shows the range of the 3 runs. Every star schema result is identical to the original, which I checked row by row, and the ETL checks prove the counts, money and readmissions match (8 checks).

| Question | Original | Star schema | Improvement | Main reason |
|---|---|---|---|---|
| 3. Readmission rate | 66–109 ms | 7.5–8.6 ms | **about 8–15× faster** | no self-join: readmission flag pre-computed in the ETL |
| 2. Diagnosis-procedure pairs | 297–349 ms | 88–104 ms | **about 3–4× faster** | count pairs of keys first, compact bridge tables |
| 4b. Total revenue per specialty | 51–84 ms | 19–34 ms | about 2.5–3× faster | money on the fact row, one join only |
| 4. Revenue by specialty and month | 72–73 ms | 42–73 ms | about the same to 1.7× | no billing → encounters → providers chain |
| 1. Encounters by specialty | 47–63 ms | 49–81 ms | about the same (0.7–1.3×) | see below |

**Questions 1 and 4 are about the same speed.** The original queries join only small tables (9 providers, 4 specialties), while the star queries join dimensions for every one of the 30,004 rows. With this amount of data, the extra lookups cost about as much as the work they save, and the times change from run to run. I tried storing the month directly in the fact table with a matching index: it did not make a clear difference, so I kept the simpler design. A gain may appear with much more data, but I did not measure that, so I do not claim it.

**What I learned:** a star schema is not automatically faster for every question. It is fastest where the ETL can do expensive work once (Q3) or where it removes long join chains (Q2, total revenue). Measuring several times, and checking that both versions give the same answer, was the only way to know.

**Limits of my comparison**
- The data ends on 31 Dec 2025, so the 276 inpatient stays discharged in December 2025 do not have a full 30-day follow-up; their readmission rate is underestimated in both databases.
- Revenue counts only encounters that have a bill (`bill_count > 0` in the star schema), like the original query that starts from billing.
- `age_group` is the age on 31 Dec 2025, not always the age on the day of the stay.

## 5. What this could show a nutrition team

I added a Clinical Nutrition service to the same tables: two dietitians, malnutrition and micronutrient diagnoses (ICD-10 E43, E44.0, D50.9, E55.9) and children aged 6–54 months. With the star schema, a nutrition question needs only one more JOIN. For example, readmission by age group in Clinical Nutrition: children 0–4 had 18.54%, adults 1–7%.

**Important:** my data is made up. My generator sends some children with severe malnutrition back to hospital on purpose, so this number shows that the design *can* answer the question, not a real fact. With real data, this kind of report could help a nutrition team see whether children treated for severe acute malnutrition come back within 30 days, which could point to problems after discharge, such as follow-up visits or access to therapeutic food at home.
