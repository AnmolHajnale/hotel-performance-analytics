-- =============================================================
-- step 6: core fact tables + merge stored procedure (cdc)
-- database: hotel_dw
-- schema:   hotel_dw.core
-- =============================================================

use role etl_role;
use warehouse hotel_compute_wh;
use schema hotel_dw.core;

-- -------------------------------------------------------------
-- fact table ddls
-- -------------------------------------------------------------

create table if not exists hotel_dw.core.fact_bookings (
    booking_id    int primary key,
    customer_sk   int,
    hotel_id      int,
    checkin_date  date,
    checkout_date date,
    total_amount  decimal(12,2),
    stay_duration int,
    is_high_value boolean,
    created_at    timestamp_ntz default current_timestamp(),
    updated_at    timestamp_ntz
);

create table if not exists hotel_dw.core.fact_reviews (
    review_id  int primary key,
    booking_id int,
    customer_sk int,
    rating     int,
    comments   varchar,
    sentiment  varchar,
    created_at timestamp_ntz default current_timestamp(),
    updated_at timestamp_ntz
);

-- -------------------------------------------------------------
-- stored procedure: load facts using merge (cdc)
-- -------------------------------------------------------------
create or replace procedure hotel_dw.core.sp_load_facts()
returns string
language sql
execute as caller
as
$$
begin

    -- ---------------------------------------------------------
    -- fact_bookings: incremental merge
    -- ---------------------------------------------------------
    merge into hotel_dw.core.fact_bookings as target
    using (
        select
            b.booking_id,
            c.customer_sk,
            b.hotel_id,
            b.checkin_date::date  as checkin_date,
            b.checkout_date::date as checkout_date,
            b.total_amount,
            b.stay_duration,
            b.is_high_value
        from hotel_dw.staging.stg_bookings      as b
        left join hotel_dw.core.dim_customers   as c
            on b.customer_id = c.customer_id
           and c.is_current  = true
    ) as source
        on target.booking_id = source.booking_id

    -- late arriving data: update if amount or high value flag changed
    when matched and (
        target.total_amount  is distinct from source.total_amount  or
        target.is_high_value is distinct from source.is_high_value
    ) then update set
        target.total_amount  = source.total_amount,
        target.is_high_value = source.is_high_value,
        target.updated_at    = current_timestamp()

    -- new booking: insert
    when not matched then insert (
        booking_id, customer_sk, hotel_id,
        checkin_date, checkout_date,
        total_amount, stay_duration, is_high_value, created_at
    ) values (
        source.booking_id, source.customer_sk, source.hotel_id,
        source.checkin_date, source.checkout_date,
        source.total_amount, source.stay_duration,
        source.is_high_value, current_timestamp()
    );

    -- ---------------------------------------------------------
    -- fact_reviews: incremental merge
    -- ---------------------------------------------------------
    merge into hotel_dw.core.fact_reviews as target
    using (
        select
            r.review_id,
            r.booking_id,
            c.customer_sk,
            r.rating,
            r.comments,
            r.sentiment
        from hotel_dw.staging.stg_reviews       as r
        left join hotel_dw.core.dim_customers   as c
            on r.customer_id = c.customer_id
           and c.is_current  = true
    ) as source
        on target.review_id = source.review_id

    when matched and (
        target.rating    is distinct from source.rating    or
        target.sentiment is distinct from source.sentiment
    ) then update set
        target.rating     = source.rating,
        target.sentiment  = source.sentiment,
        target.updated_at = current_timestamp()

    when not matched then insert (
        review_id, booking_id, customer_sk,
        rating, comments, sentiment, created_at
    ) values (
        source.review_id, source.booking_id, source.customer_sk,
        source.rating, source.comments,
        source.sentiment, current_timestamp()
    );

    return 'fact tables loaded successfully';
end;
$$;
