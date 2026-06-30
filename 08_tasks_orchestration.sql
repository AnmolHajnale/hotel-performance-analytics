-- =============================================================
-- step 8: snowflake tasks (pipeline orchestration)
-- runs every 12 hours: 6am and 6pm utc
-- database: hotel_dw
-- schema:   hotel_dw.core
-- =============================================================

use role etl_role;
use warehouse hotel_compute_wh;
use schema hotel_dw.core;

-- -------------------------------------------------------------
-- task 1: load staging (root task with schedule)
-- -------------------------------------------------------------
create or replace task task_load_staging
    warehouse = hotel_compute_wh
    schedule  = 'using cron 0 6,18 * * * utc'
    comment   = 'step 1: raw streams -> staging tables'
as
call hotel_dw.staging.sp_load_staging();

-- -------------------------------------------------------------
-- task 2: load dimensions (runs after staging)
-- -------------------------------------------------------------
create or replace task task_load_dimensions
    warehouse = hotel_compute_wh
    after     task_load_staging
    comment   = 'step 2: staging -> core dimensions (scd)'
as
call hotel_dw.core.sp_load_dimensions();

-- -------------------------------------------------------------
-- task 3: load facts (runs after dimensions)
-- -------------------------------------------------------------
create or replace task task_load_facts
    warehouse = hotel_compute_wh
    after     task_load_dimensions
    comment   = 'step 3: staging -> core facts (merge/cdc)'
as
call hotel_dw.core.sp_load_facts();

-- -------------------------------------------------------------
-- task 4: refresh marts (runs after facts)
-- -------------------------------------------------------------
create or replace task task_refresh_marts
    warehouse = hotel_compute_wh
    after     task_load_facts
    comment   = 'step 4: core -> mart tables (full refresh)'
as
begin
    create or replace table hotel_dw.mart.mart_revenue as
    select
        h.hotel_id, h.hotel_name, h.city, h.stars,
        date_trunc('month', f.checkin_date)             as booking_month,
        count(*)                                        as total_bookings,
        sum(f.total_amount)                             as total_revenue,
        avg(f.total_amount)                             as avg_booking_value,
        sum(case when f.is_high_value then 1 else 0 end) as high_value_count
    from hotel_dw.core.fact_bookings as f
    join hotel_dw.core.dim_hotels    as h on f.hotel_id = h.hotel_id
    where f.total_amount is not null
    group by 1, 2, 3, 4, 5;

    create or replace table hotel_dw.mart.mart_occupancy as
    select
        h.hotel_id, h.hotel_name, h.city, r.room_type,
        count(f.booking_id) as total_bookings,
        avg(f.stay_duration) as avg_stay_days,
        sum(f.stay_duration) as total_room_nights
    from hotel_dw.core.fact_bookings  as f
    join hotel_dw.core.dim_hotels     as h on f.hotel_id  = h.hotel_id
    join hotel_dw.core.dim_room_rates as r on r.hotel_id  = h.hotel_id
                                          and r.is_current = true
    group by 1, 2, 3, 4;

    create or replace table hotel_dw.mart.mart_customer_segments as
    select
        c.customer_id, c.customer_name, c.city,
        count(f.booking_id)  as total_bookings,
        sum(f.total_amount)  as lifetime_value,
        avg(f.total_amount)  as avg_spend_per_booking,
        max(f.checkin_date)  as last_booking_date,
        case
            when sum(f.total_amount) >= 50000 then 'platinum'
            when sum(f.total_amount) >= 20000 then 'gold'
            when sum(f.total_amount) >= 5000  then 'silver'
            else 'bronze'
        end as customer_tier
    from hotel_dw.core.fact_bookings as f
    join hotel_dw.core.dim_customers as c on f.customer_sk = c.customer_sk
    where f.total_amount is not null
    group by 1, 2, 3;

    create or replace table hotel_dw.mart.mart_satisfaction as
    select
        h.hotel_id, h.hotel_name, h.city,
        count(r.review_id)                                         as total_reviews,
        avg(r.rating)                                              as avg_rating,
        sum(case when lower(r.sentiment) = 'positive' then 1 else 0 end) as positive_count,
        sum(case when lower(r.sentiment) = 'neutral'  then 1 else 0 end) as neutral_count,
        sum(case when lower(r.sentiment) = 'negative' then 1 else 0 end) as negative_count,
        round(
            sum(case when lower(r.sentiment) = 'positive' then 1 else 0 end)
            / nullif(count(r.review_id), 0) * 100, 1
        )                                                                  as positive_pct
    from hotel_dw.core.fact_reviews  as r
    join hotel_dw.core.fact_bookings as b on r.booking_id = b.booking_id
    join hotel_dw.core.dim_hotels    as h on b.hotel_id   = h.hotel_id
    where r.rating is not null
    group by 1, 2, 3;

    create or replace table hotel_dw.mart.mart_staff as
    select
        h.hotel_id, h.hotel_name, h.city,
        s.role, s.shift,
        count(s.staff_sk) as staff_count
    from hotel_dw.core.dim_staff  as s
    join hotel_dw.core.dim_hotels as h on s.hotel_id = h.hotel_id
    where s.is_current = true
    group by 1, 2, 3, 4, 5;
end;

-- -------------------------------------------------------------
-- activate all tasks
-- important: resume child tasks first, then root task
-- -------------------------------------------------------------
alter task task_refresh_marts   resume;
alter task task_load_facts      resume;
alter task task_load_dimensions resume;
alter task task_load_staging    resume;  -- root task: has the schedule

-- -------------------------------------------------------------
-- monitor task runs
-- -------------------------------------------------------------
select
    name,
    state,
    scheduled_time,
    completed_time,
    error_message
from table(information_schema.task_history(
    scheduled_time_range_start => dateadd('hour', -24, current_timestamp())
))
order by scheduled_time desc;
