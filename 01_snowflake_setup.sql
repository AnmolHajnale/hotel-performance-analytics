-- =============================================================
-- step 1: snowflake setup
-- database: hotel_dw
-- warehouse: hotel_compute_wh
-- =============================================================

use role accountadmin;

-- -------------------------------------------------------------
-- warehouse
-- -------------------------------------------------------------
create warehouse if not exists hotel_compute_wh
    warehouse_size      = 'x-small'
    auto_suspend        = 60
    auto_resume         = true
    initially_suspended = true;

-- -------------------------------------------------------------
-- database + schemas
-- -------------------------------------------------------------
create database if not exists hotel_dw;

create schema if not exists hotel_dw.raw;
create schema if not exists hotel_dw.staging;
create schema if not exists hotel_dw.core;
create schema if not exists hotel_dw.mart;

-- -------------------------------------------------------------
-- roles
-- -------------------------------------------------------------
create role if not exists etl_role;
create role if not exists analyst_role;

-- etl_role: full access to all schemas
grant usage on warehouse hotel_compute_wh     to role etl_role;
grant usage on database  hotel_dw             to role etl_role;
grant all   on schema    hotel_dw.raw         to role etl_role;
grant all   on schema    hotel_dw.staging     to role etl_role;
grant all   on schema    hotel_dw.core        to role etl_role;
grant all   on schema    hotel_dw.mart        to role etl_role;

-- analyst_role: read only on mart
grant usage  on warehouse hotel_compute_wh        to role analyst_role;
grant usage  on database  hotel_dw                to role analyst_role;
grant usage  on schema    hotel_dw.mart           to role analyst_role;
grant select on all tables in schema hotel_dw.mart    to role analyst_role;
grant select on future tables in schema hotel_dw.mart to role analyst_role;

-- assign roles to your user
grant role etl_role     to user your_username;
grant role analyst_role to user your_username;

-- -------------------------------------------------------------
-- storage integration (snowflake <-> s3)
-- -------------------------------------------------------------
create storage integration if not exists s3_hotel_integration
    type                      = external_stage
    storage_provider          = 's3'
    enabled                   = true
    storage_aws_role_arn      = 'arn:aws:iam::your_account_id:role/SnowflakeS3Role'
    storage_allowed_locations = ('s3://hospitality-raw-bucket/');

-- run this and copy storage_aws_iam_user_arn + storage_aws_external_id
-- paste them into aws iam role trust policy
desc integration s3_hotel_integration;
