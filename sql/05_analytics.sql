-- =====================================================================
-- 05_analytics.sql  -  Business-ready data (a small "star schema")
--   DIM_CUSTOMERS, DIM_PRODUCTS  -> who & what
--   FACT_ORDERS                  -> what happened (one row per order)
--   DAILY_SALES                  -> a summary table for dashboards
-- =====================================================================

USE ROLE PIPELINE_ROLE;
USE WAREHOUSE PIPELINE_WH;
USE SCHEMA SALES_DB.ANALYTICS;

CREATE OR REPLACE VIEW DIM_CUSTOMERS AS
SELECT customer_id,
       first_name || ' ' || last_name AS full_name,
       email, city, signup_date
FROM SALES_DB.STAGING.STG_CUSTOMERS;

CREATE OR REPLACE VIEW DIM_PRODUCTS AS
SELECT product_id, product_name, category, unit_price
FROM SALES_DB.STAGING.STG_PRODUCTS;

CREATE OR REPLACE VIEW FACT_ORDERS AS
SELECT
    o.order_id,
    o.order_date,
    o.customer_id,
    o.product_id,
    o.quantity,
    p.unit_price,
    o.quantity * p.unit_price  AS order_amount,
    o.status
FROM SALES_DB.STAGING.STG_ORDERS o
LEFT JOIN SALES_DB.STAGING.STG_PRODUCTS p ON o.product_id = p.product_id;

-- A physical summary table. Dashboards read this instead of re-calculating every time.
CREATE OR REPLACE TABLE DAILY_SALES AS
SELECT
    order_date,
    COUNT(*)                                                    AS total_orders,
    COUNT_IF(status = 'CANCELLED')                              AS cancelled_orders,
    SUM(IFF(status <> 'CANCELLED', quantity, 0))                AS items_sold,
    ROUND(SUM(IFF(status <> 'CANCELLED', order_amount, 0)), 2)  AS revenue,
    COUNT(DISTINCT customer_id)                                 AS unique_customers
FROM FACT_ORDERS
GROUP BY order_date;

-- Handy views for analysis
CREATE OR REPLACE VIEW SALES_BY_CATEGORY AS
SELECT p.category,
       COUNT(*)                     AS orders,
       ROUND(SUM(f.order_amount),2) AS revenue
FROM FACT_ORDERS f JOIN DIM_PRODUCTS p ON f.product_id = p.product_id
WHERE f.status <> 'CANCELLED'
GROUP BY p.category;

CREATE OR REPLACE VIEW SALES_BY_CITY AS
SELECT c.city,
       COUNT(*)                     AS orders,
       ROUND(SUM(f.order_amount),2) AS revenue
FROM FACT_ORDERS f JOIN DIM_CUSTOMERS c ON f.customer_id = c.customer_id
WHERE f.status <> 'CANCELLED'
GROUP BY c.city;

-- Let's look at the results!
SELECT * FROM DAILY_SALES ORDER BY order_date;
SELECT * FROM SALES_BY_CATEGORY ORDER BY revenue DESC;
SELECT * FROM SALES_BY_CITY ORDER BY revenue DESC;
