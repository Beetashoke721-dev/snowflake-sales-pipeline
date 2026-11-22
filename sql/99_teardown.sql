-- =====================================================================
-- 99_teardown.sql  -  Delete EVERYTHING this project created.
-- Only run this when you're completely done (or want to start fresh).
-- =====================================================================

USE ROLE ACCOUNTADMIN;

ALTER TASK IF EXISTS SALES_DB.PIPELINE.LOAD_ORDERS_TASK SUSPEND;

DROP DATABASE  IF EXISTS SALES_DB;      -- tables, views, stage, stream, tasks
DROP WAREHOUSE IF EXISTS PIPELINE_WH;
DROP ROLE      IF EXISTS PIPELINE_ROLE;
