-- =====================================================================
-- 01_setup.sql  -  One-time account setup
-- Run this in a Snowsight worksheet as ACCOUNTADMIN (Projects > Worksheets).
-- Creates: a role, a small warehouse, the database and 4 schemas.
-- =====================================================================

USE ROLE ACCOUNTADMIN;

-- 1. A dedicated role for the pipeline (good practice: don't run pipelines as ACCOUNTADMIN)
CREATE ROLE IF NOT EXISTS PIPELINE_ROLE;
GRANT ROLE PIPELINE_ROLE TO ROLE SYSADMIN;

-- give the role to YOU (the user currently logged in)
SET my_user = '"' || CURRENT_USER() || '"';
GRANT ROLE PIPELINE_ROLE TO USER IDENTIFIER($my_user);

-- 2. Compute: the smallest warehouse, auto-suspends after 60s idle to save credits
CREATE WAREHOUSE IF NOT EXISTS PIPELINE_WH
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE;
GRANT USAGE, OPERATE ON WAREHOUSE PIPELINE_WH TO ROLE PIPELINE_ROLE;

-- 3. Storage: one database, owned by our pipeline role
CREATE DATABASE IF NOT EXISTS SALES_DB;
GRANT OWNERSHIP ON DATABASE SALES_DB TO ROLE PIPELINE_ROLE COPY CURRENT GRANTS;

-- 4. Allow the role to run scheduled Tasks (needed in step 06)
GRANT EXECUTE TASK ON ACCOUNT TO ROLE PIPELINE_ROLE;

-- 5. Switch to the pipeline role and create the layers (schemas)
USE ROLE PIPELINE_ROLE;
USE WAREHOUSE PIPELINE_WH;
USE DATABASE SALES_DB;

CREATE SCHEMA IF NOT EXISTS RAW;        -- data exactly as it arrived
CREATE SCHEMA IF NOT EXISTS STAGING;    -- cleaned, typed, de-duplicated
CREATE SCHEMA IF NOT EXISTS ANALYTICS;  -- business-ready tables & views
CREATE SCHEMA IF NOT EXISTS PIPELINE;   -- automation objects (tasks)

SHOW SCHEMAS IN DATABASE SALES_DB;
