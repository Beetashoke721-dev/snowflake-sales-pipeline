-- =====================================================================
-- 07_data_quality.sql  -  Is the pipeline healthy? Is the data correct?
-- Every "check" query should return the value in the comment next to it.
-- =====================================================================

USE ROLE PIPELINE_ROLE;
USE WAREHOUSE PIPELINE_WH;
USE DATABASE SALES_DB;

-- 1. Row counts through each layer
SELECT 'raw_orders' AS layer,  COUNT(*) AS row_count FROM RAW.RAW_ORDERS
UNION ALL SELECT 'stg_orders',     COUNT(*) FROM STAGING.STG_ORDERS
UNION ALL SELECT 'rejected_orders',COUNT(*) FROM STAGING.REJECTED_ORDERS
UNION ALL SELECT 'fact_orders',    COUNT(*) FROM ANALYTICS.FACT_ORDERS;

-- 2. No duplicate orders in staging                       -> expect 0
SELECT COUNT(*) AS duplicate_order_ids
FROM (SELECT order_id FROM STAGING.STG_ORDERS GROUP BY order_id HAVING COUNT(*) > 1);

-- 3. No orders for unknown customers or products ("orphans")  -> expect 0
SELECT COUNT(*) AS orphan_orders
FROM STAGING.STG_ORDERS o
LEFT JOIN STAGING.STG_CUSTOMERS c ON o.customer_id = c.customer_id
LEFT JOIN STAGING.STG_PRODUCTS  p ON o.product_id  = p.product_id
WHERE c.customer_id IS NULL OR p.product_id IS NULL;

-- 4. No missing required values                            -> expect 0
SELECT COUNT(*) AS rows_with_nulls
FROM STAGING.STG_ORDERS
WHERE customer_id IS NULL OR product_id IS NULL OR order_date IS NULL OR status IS NULL;

-- 5. Only known status values                              -> expect only 4 values
SELECT status, COUNT(*) FROM STAGING.STG_ORDERS GROUP BY status ORDER BY 2 DESC;

-- 6. Revenue in the summary table matches the detail data  -> expect TRUE
SELECT
    (SELECT SUM(revenue) FROM ANALYTICS.DAILY_SALES)
  = (SELECT ROUND(SUM(order_amount), 2) FROM ANALYTICS.FACT_ORDERS WHERE status <> 'CANCELLED')
  AS revenue_matches;

-- 7. Load history: which files were loaded, and any errors?
SELECT file_name, table_name, row_count, row_parsed, error_count, status, last_load_time
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
        TABLE_NAME => 'RAW.RAW_ORDERS',
        START_TIME => DATEADD(DAY, -7, CURRENT_TIMESTAMP())))
ORDER BY last_load_time DESC;

-- 8. Task run history: did the automated pipeline succeed?
SELECT name, state, scheduled_time, completed_time, error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
        SCHEDULED_TIME_RANGE_START => DATEADD(HOUR, -24, CURRENT_TIMESTAMP())))
ORDER BY scheduled_time DESC
LIMIT 20;
