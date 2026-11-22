-- =====================================================================
-- 02_raw_layer.sql  -  Where files land and raw tables live
-- Creates: a CSV file format, an internal stage, 3 raw tables, 1 stream
-- =====================================================================

USE ROLE PIPELINE_ROLE;
USE WAREHOUSE PIPELINE_WH;
USE SCHEMA SALES_DB.RAW;

-- How to read our CSV files
CREATE OR REPLACE FILE FORMAT CSV_FORMAT
    TYPE                         = CSV
    SKIP_HEADER                  = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF                      = ('', 'NULL')
    EMPTY_FIELD_AS_NULL          = TRUE;

-- An internal stage = a folder inside Snowflake where we upload files
CREATE STAGE IF NOT EXISTS LANDING_STAGE
    COMMENT = 'Landing zone for ShopEasy CSV files';

-- Raw tables: every column is STRING on purpose.
-- Rule of the RAW layer: store data exactly as received, never fail a load
-- because of a bad value. We fix types in STAGING.
-- _file_name and _loaded_at are "audit columns": where & when each row came from.
CREATE TABLE IF NOT EXISTS RAW_CUSTOMERS (
    customer_id  STRING,
    first_name   STRING,
    last_name    STRING,
    email        STRING,
    city         STRING,
    signup_date  STRING,
    _file_name   STRING,
    _loaded_at   TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS RAW_PRODUCTS (
    product_id    STRING,
    product_name  STRING,
    category      STRING,
    unit_price    STRING,
    _file_name    STRING,
    _loaded_at    TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS RAW_ORDERS (
    order_id     STRING,
    customer_id  STRING,
    product_id   STRING,
    quantity     STRING,
    order_date   STRING,
    status       STRING,
    _file_name   STRING,
    _loaded_at   TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

-- A STREAM tracks new rows added to RAW_ORDERS since we last read it.
-- This is how we process only NEW data instead of everything every time.
CREATE STREAM IF NOT EXISTS RAW_ORDERS_STREAM
    ON TABLE RAW_ORDERS
    APPEND_ONLY = TRUE;

SHOW TABLES IN SCHEMA SALES_DB.RAW;
