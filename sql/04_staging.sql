-- =====================================================================
-- 04_staging.sql  -  Clean the data
--   * customers & products: small -> simple VIEWS (always up to date)
--   * orders: big & growing  -> a TABLE updated incrementally with MERGE
-- =====================================================================

USE ROLE PIPELINE_ROLE;
USE WAREHOUSE PIPELINE_WH;
USE SCHEMA SALES_DB.STAGING;

-- ---------- Customers: trim spaces, fix casing, cast types, remove duplicates
CREATE OR REPLACE VIEW STG_CUSTOMERS AS
SELECT
    TRY_TO_NUMBER(customer_id)   AS customer_id,
    INITCAP(TRIM(first_name))    AS first_name,
    INITCAP(TRIM(last_name))     AS last_name,
    LOWER(TRIM(email))           AS email,
    INITCAP(TRIM(city))          AS city,
    TRY_TO_DATE(signup_date)     AS signup_date
FROM SALES_DB.RAW.RAW_CUSTOMERS
WHERE TRY_TO_NUMBER(customer_id) IS NOT NULL
-- keep only one row per customer (the most recently loaded one)
QUALIFY ROW_NUMBER() OVER (PARTITION BY TRY_TO_NUMBER(customer_id) ORDER BY _loaded_at DESC) = 1;

-- ---------- Products
CREATE OR REPLACE VIEW STG_PRODUCTS AS
SELECT
    TRY_TO_NUMBER(product_id)           AS product_id,
    TRIM(product_name)                  AS product_name,
    TRIM(category)                      AS category,
    TRY_TO_NUMBER(unit_price, 10, 2)    AS unit_price
FROM SALES_DB.RAW.RAW_PRODUCTS
WHERE TRY_TO_NUMBER(product_id) IS NOT NULL
QUALIFY ROW_NUMBER() OVER (PARTITION BY TRY_TO_NUMBER(product_id) ORDER BY _loaded_at DESC) = 1;

-- ---------- Orders: a real table, filled incrementally
CREATE TABLE IF NOT EXISTS STG_ORDERS (
    order_id     NUMBER,
    customer_id  NUMBER,
    product_id   NUMBER,
    quantity     NUMBER,
    order_date   DATE,
    status       STRING,
    _updated_at  TIMESTAMP_LTZ
);

-- MERGE = "insert new orders, update existing ones" (an UPSERT).
-- We read from the STREAM, so only rows not processed yet are used.
-- After this statement succeeds, the stream is automatically emptied.
MERGE INTO STG_ORDERS AS t
USING (
    SELECT
        TRY_TO_NUMBER(order_id)     AS order_id,
        TRY_TO_NUMBER(customer_id)  AS customer_id,
        TRY_TO_NUMBER(product_id)   AS product_id,
        TRY_TO_NUMBER(quantity)     AS quantity,
        TRY_TO_DATE(order_date)     AS order_date,
        UPPER(TRIM(status))         AS status
    FROM SALES_DB.RAW.RAW_ORDERS_STREAM
    WHERE TRY_TO_NUMBER(order_id) IS NOT NULL
      AND TRY_TO_NUMBER(quantity) > 0          -- drop zero/negative quantities
      AND TRY_TO_DATE(order_date) IS NOT NULL  -- drop unreadable dates
    QUALIFY ROW_NUMBER() OVER (PARTITION BY TRY_TO_NUMBER(order_id) ORDER BY _loaded_at DESC) = 1
) AS s
ON t.order_id = s.order_id
WHEN MATCHED THEN UPDATE SET
    t.customer_id = s.customer_id,
    t.product_id  = s.product_id,
    t.quantity    = s.quantity,
    t.order_date  = s.order_date,
    t.status      = s.status,
    t._updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT
    (order_id, customer_id, product_id, quantity, order_date, status, _updated_at)
VALUES
    (s.order_id, s.customer_id, s.product_id, s.quantity, s.order_date, s.status, CURRENT_TIMESTAMP());

-- ---------- Rejected rows: so we can SEE what the cleaning threw away
CREATE OR REPLACE VIEW REJECTED_ORDERS AS
SELECT *,
    CASE
        WHEN TRY_TO_NUMBER(order_id) IS NULL   THEN 'bad order_id'
        WHEN TRY_TO_NUMBER(quantity) IS NULL
          OR TRY_TO_NUMBER(quantity) <= 0      THEN 'bad quantity'
        WHEN TRY_TO_DATE(order_date) IS NULL   THEN 'bad order_date'
    END AS reject_reason
FROM SALES_DB.RAW.RAW_ORDERS
WHERE TRY_TO_NUMBER(order_id) IS NULL
   OR TRY_TO_NUMBER(quantity) IS NULL OR TRY_TO_NUMBER(quantity) <= 0
   OR TRY_TO_DATE(order_date) IS NULL;

-- Results
SELECT COUNT(*) AS stg_orders      FROM STG_ORDERS;
SELECT COUNT(*) AS stg_customers   FROM STG_CUSTOMERS;
SELECT reject_reason, COUNT(*) AS rejected FROM REJECTED_ORDERS GROUP BY 1;
SELECT COUNT(*) AS stream_rows_left FROM SALES_DB.RAW.RAW_ORDERS_STREAM;  -- should be 0 now
