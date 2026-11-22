# ShopEasy Sales Pipeline on Snowflake ❄️

A beginner-friendly, end-to-end **data pipeline** built on Snowflake.
It takes raw CSV files from a (fake) online shop, loads them into Snowflake, cleans them,
models them for analytics, checks data quality, and then **runs automatically** on a schedule.

**Level:** easy → medium  ·  **Time:** one weekend (≈ 4–6 hours)  ·  **Cost:** free (Snowflake trial)

---

## What you will build

```
 Your laptop                         Snowflake (SALES_DB)
 ───────────                         ──────────────────────────────────────────────────────────
 generate_data.py                    RAW schema            STAGING schema        ANALYTICS schema
   │  CSV files                      ───────────           ──────────────        ────────────────
   ▼                                                        STG_CUSTOMERS (view)  DIM_CUSTOMERS
 upload_files.py ──PUT──► LANDING_STAGE ──COPY INTO──► RAW_CUSTOMERS ─────►     DIM_PRODUCTS
                                         RAW_PRODUCTS  ─────► STG_PRODUCTS (view)  FACT_ORDERS
                                         RAW_ORDERS                                DAILY_SALES (table)
                                            │                                      SALES_BY_CITY
                                            ▼ STREAM (new rows only)               SALES_BY_CATEGORY
                                         RAW_ORDERS_STREAM ──MERGE──► STG_ORDERS ──►
                                                                     REJECTED_ORDERS (view)

 PIPELINE schema:  LOAD_ORDERS_TASK ──► MERGE_ORDERS_TASK ──► REFRESH_DAILY_SALES_TASK   (every 5 min)
```

This layered design (raw → staging → analytics) is called the **medallion architecture**
(bronze → silver → gold). It's what real companies use, just at a bigger scale.

### Skills you'll practise
| Concept | Where |
|---|---|
| Roles, warehouses, databases, schemas | `sql/01_setup.sql` |
| File formats & internal stages | `sql/02_raw_layer.sql` |
| Uploading files with `PUT` from Python | `scripts/upload_files.py` |
| Bulk loading with `COPY INTO` | `sql/03_load_raw.sql` |
| Data cleaning, `TRY_TO_*`, de-duplication with `QUALIFY` | `sql/04_staging.sql` |
| Incremental loads with **Streams** + `MERGE` (upsert) | `sql/04_staging.sql` |
| Star schema (dimensions & facts) | `sql/05_analytics.sql` |
| Orchestration with **Tasks** (a DAG) | `sql/06_tasks.sql` |
| Data quality checks & monitoring | `sql/07_data_quality.sql` |
| Git, GitHub, and a CI workflow | Step 13 |

---

## Project structure

```
snowflake-sales-pipeline/
├── data_generator/
│   └── generate_data.py      # creates fake CSV data (step 3)
├── scripts/
│   ├── sf_connection.py      # shared Snowflake login code
│   ├── test_connection.py    # "can I connect?" check
│   ├── upload_files.py       # PUT local CSVs into the Snowflake stage
│   └── run_sql.py            # run any .sql file from the terminal
├── sql/
│   ├── 01_setup.sql          # role, warehouse, database, schemas
│   ├── 02_raw_layer.sql      # file format, stage, raw tables, stream
│   ├── 03_load_raw.sql       # COPY INTO raw tables
│   ├── 04_staging.sql        # cleaning + incremental MERGE
│   ├── 05_analytics.sql      # dims, fact, summary tables
│   ├── 06_tasks.sql          # automation (task DAG)
│   ├── 07_data_quality.sql   # tests & monitoring
│   └── 99_teardown.sql       # delete everything
├── .github/workflows/ci.yml  # automatic checks on GitHub
├── .env.example              # template for your credentials
├── .gitignore
├── requirements.txt
└── README.md
```

---

## Step 0 — Install the tools (≈ 20 min)

| Tool | Why | Get it |
|---|---|---|
| **Python 3.9+** | run the scripts | python.org (Windows: tick *"Add Python to PATH"*) |
| **Git** | version control | git-scm.com (Windows: this also installs *Git Bash* — use it as your terminal) |
| **VS Code** | edit code | code.visualstudio.com |
| **GitHub account** | host your code | github.com |
| **Snowflake trial** | the data platform | signup.snowflake.com — choose *Enterprise* edition, any cloud, a region near you (e.g. AWS Mumbai) |

Check in a terminal:
```bash
python --version     # (on Mac/Linux it may be python3)
git --version
```

---

## Step 1 — Get the project on your laptop

Unzip this project somewhere simple, e.g. `C:\projects\snowflake-sales-pipeline` or `~/projects/snowflake-sales-pipeline`,
then open the folder in VS Code (*File → Open Folder*) and open a terminal (*Terminal → New Terminal*).

---

## Step 2 — Create a Python virtual environment

A virtual environment keeps this project's packages separate from everything else on your computer.

```bash
python -m venv .venv

# activate it
# Windows (Git Bash):   source .venv/Scripts/activate
# Windows (PowerShell): .venv\Scripts\Activate.ps1
# Mac / Linux:          source .venv/bin/activate

pip install -r requirements.txt
```
You'll see `(.venv)` at the start of your terminal line when it's active.

---

## Step 3 — Get the data 📦

Real pipelines pull data from apps, APIs or databases. Here we **simulate** a shop's daily export:

```bash
python data_generator/generate_data.py
```
This creates in `data/`:

| File | Rows | What it is |
|---|---|---|
| `customers.csv` | 205 | 200 customers + 5 duplicates |
| `products.csv` | 30 | products in 4 categories |
| `orders_batch_1.csv` | 1,010 | orders for 1–7 Nov (day 1 of our pipeline) |
| `orders_batch_2.csv` | 610 | *new* orders for 8–10 Nov + status updates for 100 old orders |

Open them in VS Code. Notice the data is **messy on purpose**: extra spaces, `UPPER`/`lower` case,
duplicates, quantities of `0` or `-3`, and dates like `not-a-date`. Cleaning this is your job in step 8.

> 💡 Later, try swapping in a real dataset (Kaggle has many e-commerce CSVs). The pipeline pattern stays the same.

---

## Step 4 — Set up Snowflake (in the browser)

1. Log in to Snowsight (the Snowflake web UI).
2. Go to **Projects → Workspaces/Worksheets → + (new SQL worksheet)**.
3. Paste the whole of `sql/01_setup.sql` and click **Run All** (the ▶ dropdown → *Run All*, or `Ctrl/Cmd + Shift + Enter`).

You now have:
- **PIPELINE_ROLE** — a role just for this project (you never want pipelines running as `ACCOUNTADMIN`)
- **PIPELINE_WH** — an X-Small warehouse (the compute) that sleeps after 60 s idle → cheap
- **SALES_DB** with schemas **RAW, STAGING, ANALYTICS, PIPELINE**

> **Warehouse vs database?** In Snowflake, *storage* (database) and *compute* (warehouse) are separate.
> The warehouse is the engine that runs queries; you only pay while it's running.

Find your **account identifier** (you need it in the next step) by running in the worksheet:
```sql
SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME() AS account_identifier;
```

---

## Step 5 — Connect Python to Snowflake 🔑

Snowflake is phasing out password-only logins for scripts and tools, so the professional way is
**key-pair authentication**. (Trial accounts can still use a password — see Option B.)

### Option A (recommended): key pair

1. In your project folder terminal (Git Bash on Windows), create a key pair:
   ```bash
   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8 -nocrypt
   openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
   ```
   `rsa_key.p8` is your **private** key (secret!). `rsa_key.pub` is the public key you give to Snowflake.
   Both are already in `.gitignore`, so they won't be pushed to GitHub.

2. Open `rsa_key.pub`, copy the long text **between** `-----BEGIN PUBLIC KEY-----` and `-----END PUBLIC KEY-----`
   (join it into one line), then run in Snowsight:
   ```sql
   USE ROLE ACCOUNTADMIN;
   ALTER USER <your_username> SET RSA_PUBLIC_KEY = 'MIIBIjANBgkqh...your key...';
   DESC USER <your_username>;   -- RSA_PUBLIC_KEY_FP should now have a value
   ```

3. Create your `.env` file:
   ```bash
   cp .env.example .env
   ```
   and fill in `SNOWFLAKE_ACCOUNT` (from step 4) and `SNOWFLAKE_USER`. Keep `SNOWFLAKE_PRIVATE_KEY_PATH=./rsa_key.p8`.

### Option B (trial accounts only): password
Fill in `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD` in `.env` and **empty** the `SNOWFLAKE_PRIVATE_KEY_PATH=` line.

### Test it
```bash
python scripts/test_connection.py
```
Expected: `Connected to Snowflake!` with role `PIPELINE_ROLE`. If not, see **Troubleshooting** at the bottom.

---

## How to run the SQL files (steps 6–11)

You can run each SQL file in **either** way — pick whichever you like:

- **Snowsight:** paste the file into a worksheet → *Run All*. Best for learning: you see every result as a table.
- **Terminal:** `python scripts/run_sql.py sql/<file>.sql` — prints a preview of each result.

👉 Tip: the first time, use Snowsight and run statements **one at a time** (`Ctrl/Cmd + Enter`) so you understand each one.

---

## Step 6 — Build the RAW layer

Run `sql/02_raw_layer.sql`. It creates:

- **CSV_FORMAT** — tells Snowflake how to read our files (skip the header, handle quotes, treat empty as NULL).
- **LANDING_STAGE** — an *internal stage*: a file storage area inside Snowflake.
- **RAW_CUSTOMERS / RAW_PRODUCTS / RAW_ORDERS** — every column is `STRING`. That's deliberate:
  the raw layer stores data *exactly* as received, so a bad value never breaks a load.
  `_file_name` and `_loaded_at` are **audit columns** — you can always trace a row back to its file.
- **RAW_ORDERS_STREAM** — a *stream* is like a bookmark. It records which rows are new since
  you last consumed it, so later steps process only new data.

---

## Step 7 — Ingest: upload files to the stage

```bash
python scripts/upload_files.py --batch 1
```
This uses Snowflake's `PUT` command to upload `customers.csv`, `products.csv` and `orders_batch_1.csv`
(compressed to `.gz`) into `@LANDING_STAGE/customers/`, `/products/` and `/orders/`.

Check in Snowsight: `LIST @SALES_DB.RAW.LANDING_STAGE;`

> **Alternative without Python:** In Snowsight, go to *Data → Databases → SALES_DB → RAW → Stages → LANDING_STAGE → + Files*
> and upload the files into the right folder by hand.

---

## Step 8 — Load: COPY INTO raw tables

Run `sql/03_load_raw.sql`. You'll:
1. `LIST` the stage,
2. **query a file directly** before loading it (`SELECT $1, $2 ... FROM @stage`) — very handy for debugging,
3. `COPY INTO` the three raw tables.

Expected counts: **RAW_CUSTOMERS 205 · RAW_PRODUCTS 30 · RAW_ORDERS 1,010**, and the stream shows **1,010** new rows.

> 🧪 **Try this:** run the `COPY INTO RAW_ORDERS` statement again. It loads **0 rows** — Snowflake remembers
> which files it already loaded. This makes re-running a pipeline safe (*idempotent*).

---

## Step 9 — Clean: the STAGING layer

Run `sql/04_staging.sql`. What happens:

| Problem in raw data | Fix |
|---|---|
| `"  Kolkata  "`, `MUMBAI` | `INITCAP(TRIM(...))` |
| Text that should be numbers/dates | `TRY_TO_NUMBER`, `TRY_TO_DATE` (return NULL instead of failing) |
| Duplicate rows | `QUALIFY ROW_NUMBER() OVER (PARTITION BY id ORDER BY _loaded_at DESC) = 1` |
| Quantity ≤ 0, unreadable dates | filtered out and visible in the **REJECTED_ORDERS** view |
| Orders that change status later | `MERGE` = update if the order exists, insert if new (an *upsert*) |

Customers and products are small → simple **views**. Orders grow every day → a real **table** filled
**incrementally** from the stream.

Expected: **STG_ORDERS 992**, **STG_CUSTOMERS 200**, **8 rejected** rows, and the stream is back to **0**
(a successful MERGE "consumes" the stream).

---

## Step 10 — Model: the ANALYTICS layer

Run `sql/05_analytics.sql`. This builds a small **star schema**:

- **DIM_CUSTOMERS**, **DIM_PRODUCTS** — descriptive data (*who*, *what*)
- **FACT_ORDERS** — one row per order with `order_amount = quantity × unit_price`
- **DAILY_SALES** — a pre-aggregated table (orders, items, revenue, customers per day) for dashboards
- **SALES_BY_CATEGORY**, **SALES_BY_CITY** — ready-made views for analysis

> 📊 **Bonus:** In Snowsight, run `SELECT * FROM SALES_DB.ANALYTICS.DAILY_SALES ORDER BY order_date;`,
> click **Chart** above the results, and make a line chart of revenue by date. Your first dashboard!

---

## Step 11 — Test: data quality checks

Run `sql/07_data_quality.sql`. Each check has its expected answer in a comment, e.g.
**0 duplicate order IDs, 0 orphan orders, 0 missing values, revenue_matches = TRUE**.

In real teams these checks run automatically after each load, and someone gets alerted if one fails.

---

## Step 12 — Automate: Tasks ⏰

So far you ran everything by hand. Now let Snowflake run it. Run `sql/06_tasks.sql` — it creates a
**task graph (DAG)**:

```
LOAD_ORDERS_TASK (every 5 min) ──► MERGE_ORDERS_TASK ──► REFRESH_DAILY_SALES_TASK
```

Tasks are created **suspended**. Now let's simulate *the next day's data arriving*:

1. **Turn the pipeline on** (Snowsight):
   ```sql
   USE ROLE PIPELINE_ROLE;
   SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('SALES_DB.PIPELINE.LOAD_ORDERS_TASK');
   ```
2. **New data arrives** (terminal):
   ```bash
   python scripts/upload_files.py --batch 2
   ```
3. **Wait up to 5 minutes**, or trigger it right now:
   ```sql
   EXECUTE TASK SALES_DB.PIPELINE.LOAD_ORDERS_TASK;
   ```
4. **Watch it run** — Snowsight: *Monitoring → Task History*, or query 8 in `07_data_quality.sql`.
   Each task should show `SUCCEEDED` (refresh after a minute).
5. **Check the results:**
   ```sql
   SELECT COUNT(*) FROM SALES_DB.STAGING.STG_ORDERS;           -- 1,485  (was 992)
   SELECT MAX(order_date) FROM SALES_DB.ANALYTICS.DAILY_SALES;  -- 2026-11-10
   SELECT status, COUNT(*) FROM SALES_DB.STAGING.STG_ORDERS GROUP BY 1;  -- more SHIPPED/DELIVERED
   ```
   Notice: 100 old orders were **updated**, not duplicated — that's the MERGE doing its job.
   Re-run `07_data_quality.sql` — every check should still pass.

6. ⚠️ **Turn it off when you're done practising** (a task waking a warehouse every 5 min uses credits):
   ```sql
   ALTER TASK SALES_DB.PIPELINE.LOAD_ORDERS_TASK SUSPEND;
   ```

🎉 **That's a complete pipeline:** ingest → load → clean → model → test → automate.

---

## Step 13 — Put it on GitHub 🐙

### 13.1 Create an empty repository on GitHub
github.com → **+** (top right) → **New repository** → name it `snowflake-sales-pipeline` →
Public → **don't** tick "Add a README" (we already have one) → **Create repository**.

### 13.2 Tell Git who you are (first time only)
```bash
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

### 13.3 Commit and push
In the project folder:
```bash
git init
git add .
git status            # ⚠️ CHECK: .env, rsa_key.p8 and data/*.csv must NOT be listed!
git commit -m "Snowflake sales pipeline: raw, staging, analytics layers + tasks"
git branch -M main
git remote add origin https://github.com/<your-username>/snowflake-sales-pipeline.git
git push -u origin main
```
When asked to log in: GitHub doesn't accept your account password here. Either sign in through the
browser pop-up (Git Credential Manager, installed with Git for Windows), or create a
**Personal Access Token** (GitHub → Settings → Developer settings → Personal access tokens) and paste it as the password.

### 13.4 See CI run
Open your repo → **Actions** tab. The workflow in `.github/workflows/ci.yml` runs on every push and checks
that the Python code is valid and the data generator works. A green ✅ = passing.

### 13.5 Keep committing as you learn
Small, clear commits tell the story of your project:
```bash
git add sql/05_analytics.sql
git commit -m "Add sales by city view"
git push
```

### 13.6 Make it portfolio-ready
- Add a screenshot of your Snowsight chart to the README (`docs/revenue_chart.png`).
- Add a short "What I learned" section at the top in your own words.
- Pin the repo on your GitHub profile.

---

## Exercises (do these to really learn it)

1. **Easy** — Add a `TOP_CUSTOMERS` view in ANALYTICS: top 10 customers by revenue.
2. **Easy** — Add a check to `07_data_quality.sql`: no order date in the future.
3. **Medium** — Make a `batch 3` file with some customers who don't exist (e.g. `customer_id = 999`). What do the quality checks say? How would you handle it?
4. **Medium** — Add a `WHEN SYSTEM$STREAM_HAS_DATA('SALES_DB.RAW.RAW_ORDERS_STREAM')` condition so the merge only runs when there's new data.
5. **Medium** — Replace `DAILY_SALES` + its task with a **Dynamic Table** (`CREATE DYNAMIC TABLE ... TARGET_LAG = '5 minutes'`) and compare the two approaches.
6. **Medium+** — Make customers incremental too, with a stream and a MERGE (and keep history = an SCD Type 2 dimension).

## Where to go next
- **Snowpipe** — load files automatically the moment they land in cloud storage (S3 / Azure / GCS).
- **dbt** — the industry-standard tool for the transformation (staging/analytics) part, with built-in tests.
- **Airflow / Dagster** — orchestration outside Snowflake.
- **Streamlit in Snowflake** — build a small dashboard app on top of `ANALYTICS`.

---

## Troubleshooting

| Error | Fix |
|---|---|
| `Missing settings in .env` | You didn't create `.env` — run `cp .env.example .env` and fill it in. |
| `JWT token is invalid` | The public key in Snowflake doesn't match `rsa_key.p8`. Re-copy the key into `ALTER USER ... SET RSA_PUBLIC_KEY` (no header/footer lines, no line breaks). |
| `Incorrect username or password` / MFA errors | Use key-pair (Option A). Password login for scripts only works on trial accounts. |
| `Account ... not found` / timeouts | `SNOWFLAKE_ACCOUNT` must look like `ORGNAME-ACCOUNTNAME` (from step 4), without `.snowflakecomputing.com`. |
| `Role 'PIPELINE_ROLE' ... not authorized` | Re-run `01_setup.sql` as ACCOUNTADMIN. If your username has special characters, replace `IDENTIFIER($my_user)` with `"your_username"`. |
| `Object does not exist or not authorized` | You're probably in the wrong role. Run `USE ROLE PIPELINE_ROLE;` first. |
| `COPY` loads 0 rows | Files were already loaded (by design), or you forgot `upload_files.py`. Check `LIST @SALES_DB.RAW.LANDING_STAGE;`. |
| Task never runs | Did you run `SYSTEM$TASK_DEPENDENTS_ENABLE(...)`? Check `SHOW TASKS IN SCHEMA SALES_DB.PIPELINE;` → `state` should be `started`. |
| `python` not found (Mac/Linux) | Use `python3`. |

## Start over / clean up
Run `sql/99_teardown.sql` as ACCOUNTADMIN to delete everything this project created.
