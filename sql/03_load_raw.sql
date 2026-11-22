-- =====================================================================
-- 03_load_raw.sql  -  Copy uploaded files from the stage into raw tables
-- Run AFTER:  python scripts/upload_files.py --batch 1
-- =====================================================================

USE ROLE PIPELINE_ROLE;
USE WAREHOUSE PIPELINE_WH;
USE SCHEMA SALES_DB.RAW;

-- See what's sitting in the stage
LIST @LANDING_STAGE;

-- Peek at a file BEFORE loading it (reads the file directly - no table needed!)
SELECT $1 AS order_id, $2 AS customer_id, $4 AS quantity, $6 AS status, METADATA$FILENAME
FROM @LANDING_STAGE/orders/ (FILE_FORMAT => 'CSV_FORMAT')
LIMIT 5;

-- COPY INTO loads files into tables.
-- Nice detail: Snowflake remembers which files it already loaded (for 64 days),
-- so running COPY again will NOT load the same file twice.
COPY INTO RAW_CUSTOMERS (customer_id, first_name, last_name, email, city, signup_date, _file_name)
FROM (SELECT $1, $2, $3, $4, $5, $6, METADATA$FILENAME FROM @LANDING_STAGE/customers/)
FILE_FORMAT = (FORMAT_NAME = 'CSV_FORMAT')
ON_ERROR = 'CONTINUE';

COPY INTO RAW_PRODUCTS (product_id, product_name, category, unit_price, _file_name)
FROM (SELECT $1, $2, $3, $4, METADATA$FILENAME FROM @LANDING_STAGE/products/)
FILE_FORMAT = (FORMAT_NAME = 'CSV_FORMAT')
ON_ERROR = 'CONTINUE';

COPY INTO RAW_ORDERS (order_id, customer_id, product_id, quantity, order_date, status, _file_name)
FROM (SELECT $1, $2, $3, $4, $5, $6, METADATA$FILENAME FROM @LANDING_STAGE/orders/)
FILE_FORMAT = (FORMAT_NAME = 'CSV_FORMAT')
ON_ERROR = 'CONTINUE';

-- Check row counts
SELECT 'RAW_CUSTOMERS' AS table_name, COUNT(*) AS row_count FROM RAW_CUSTOMERS
UNION ALL SELECT 'RAW_PRODUCTS', COUNT(*) FROM RAW_PRODUCTS
UNION ALL SELECT 'RAW_ORDERS',   COUNT(*) FROM RAW_ORDERS;

-- The stream now "sees" the new orders, waiting to be processed
SELECT COUNT(*) AS new_rows_in_stream FROM RAW_ORDERS_STREAM;
