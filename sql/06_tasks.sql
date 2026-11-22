-- =====================================================================
-- 06_tasks.sql  -  Automate everything with a Task graph (DAG)
--
--   LOAD_ORDERS_TASK  (every 5 min)  : COPY new files from stage -> RAW_ORDERS
--         |
--   MERGE_ORDERS_TASK                 : stream -> STG_ORDERS (MERGE)
--         |
--   REFRESH_DAILY_SALES_TASK          : rebuild ANALYTICS.DAILY_SALES
--
-- Tasks are created SUSPENDED. Turning them on is a separate step (see bottom).
-- =====================================================================

USE ROLE PIPELINE_ROLE;
USE WAREHOUSE PIPELINE_WH;
USE SCHEMA SALES_DB.PIPELINE;

-- Task 1 (root): load any new order files. COPY skips files already loaded.
CREATE OR REPLACE TASK LOAD_ORDERS_TASK
    WAREHOUSE = PIPELINE_WH
    SCHEDULE  = '5 MINUTE'
AS
COPY INTO SALES_DB.RAW.RAW_ORDERS (order_id, customer_id, product_id, quantity, order_date, status, _file_name)
FROM (SELECT $1, $2, $3, $4, $5, $6, METADATA$FILENAME FROM @SALES_DB.RAW.LANDING_STAGE/orders/)
FILE_FORMAT = (FORMAT_NAME = 'SALES_DB.RAW.CSV_FORMAT')
ON_ERROR = 'CONTINUE';

-- Task 2: same MERGE you ran by hand in 04_staging.sql
CREATE OR REPLACE TASK MERGE_ORDERS_TASK
    WAREHOUSE = PIPELINE_WH
    AFTER LOAD_ORDERS_TASK
AS
MERGE INTO SALES_DB.STAGING.STG_ORDERS AS t
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
      AND TRY_TO_NUMBER(quantity) > 0
      AND TRY_TO_DATE(order_date) IS NOT NULL
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

-- Task 3: rebuild the summary table
CREATE OR REPLACE TASK REFRESH_DAILY_SALES_TASK
    WAREHOUSE = PIPELINE_WH
    AFTER MERGE_ORDERS_TASK
AS
INSERT OVERWRITE INTO SALES_DB.ANALYTICS.DAILY_SALES
SELECT
    order_date,
    COUNT(*),
    COUNT_IF(status = 'CANCELLED'),
    SUM(IFF(status <> 'CANCELLED', quantity, 0)),
    ROUND(SUM(IFF(status <> 'CANCELLED', order_amount, 0)), 2),
    COUNT(DISTINCT customer_id)
FROM SALES_DB.ANALYTICS.FACT_ORDERS
GROUP BY order_date;

-- ---------------------------------------------------------------------
-- TURN THE PIPELINE ON  (run these lines yourself when you're ready)
-- ---------------------------------------------------------------------
-- Resume the root task AND all tasks after it, in one go:
--   SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('SALES_DB.PIPELINE.LOAD_ORDERS_TASK');
--
-- Don't want to wait 5 minutes? Run the whole graph right now:
--   EXECUTE TASK SALES_DB.PIPELINE.LOAD_ORDERS_TASK;
--
-- TURN IT OFF when you're done practising (saves your free credits!):
--   ALTER TASK SALES_DB.PIPELINE.LOAD_ORDERS_TASK SUSPEND;
-- ---------------------------------------------------------------------

SHOW TASKS IN SCHEMA SALES_DB.PIPELINE;
