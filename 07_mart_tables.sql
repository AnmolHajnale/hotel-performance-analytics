-- =============================================================
-- step 7: mart tables (gold layer)
-- full refresh every run
-- database: hotel_dw
-- schema:   hotel_dw.mart
-- =============================================================

use role etl_role;
use warehouse hotel_compute_wh;
use schema hotel_dw.mart;

-- -------------------------------------------------------------
-- mart_revenue: revenue by hotel, city, month
-- -------------------------------------------------------------
create or replace table hotel_dw.mart.mart_revenue as
select
    h.hotel_id,
    h.hotel_name,
    h.city,
    h.stars,
    date_trunc('month', f.checkin_date)                          as booking_month,
    count(*)                                                     as total_bookings,
    sum(f.total_amount)                                          as total_revenue,
    avg(f.total_amount)                                          as avg_booking_value,
    sum(case when f.is_high_value then 1 else 0 end)             as high_value_count
from hotel_dw.core.fact_bookings  as f
join hotel_dw.core.dim_hotels     as h on f.hotel_id = h.hotel_id
where f.total_amount is not null
group by 1, 2, 3, 4, 5;

-- -------------------------------------------------------------
-- mart_occupancy: bookings per hotel and room type
-- -------------------------------------------------------------
create or replace table hotel_dw.mart.mart_occupancy as
select
    h.hotel_id,
    h.hotel_name,
    h.city,
    r.room_type,
    count(f.booking_id)                                          as total_bookings,
    avg(f.stay_duration)                                         as avg_stay_days,
    sum(f.stay_duration)                                         as total_room_nights
from hotel_dw.core.fact_bookings    as f
join hotel_dw.core.dim_hotels       as h on f.hotel_id  = h.hotel_id
join hotel_dw.core.dim_room_rates   as r on r.hotel_id  = h.hotel_id
                                        and r.is_current = true
group by 1, 2, 3, 4;

-- -------------------------------------------------------------
-- mart_customer_segments: lifetime value + tier
-- -------------------------------------------------------------
create or replace table hotel_dw.mart.mart_customer_segments as
select
    c.customer_id,
    c.customer_name,
    c.city,
    count(f.booking_id)                                          as total_bookings,
    sum(f.total_amount)                                          as lifetime_value,
    avg(f.total_amount)                                          as avg_spend_per_booking,
    max(f.checkin_date)                                          as last_booking_date,
    case
        when sum(f.total_amount) >= 50000 then 'platinum'
        when sum(f.total_amount) >= 20000 then 'gold'
        when sum(f.total_amount) >= 5000  then 'silver'
        else 'bronze'
    end                                                          as customer_tier
from hotel_dw.core.fact_bookings  as f
join hotel_dw.core.dim_customers  as c
    on f.customer_sk = c.customer_sk
where f.total_amount is not null
group by 1, 2, 3;

-- -------------------------------------------------------------
-- mart_satisfaction: avg rating + sentiment per hotel
-- -------------------------------------------------------------
create or replace table hotel_dw.mart.mart_satisfaction as
select
    h.hotel_id,
    h.hotel_name,
    h.city,
    count(r.review_id)                                           as total_reviews,
    avg(r.rating)                                                as avg_rating,
    sum(case when lower(r.sentiment) = 'positive' then 1 else 0 end)   as positive_count,
    sum(case when lower(r.sentiment) = 'neutral'  then 1 else 0 end)   as neutral_count,
    sum(case when lower(r.sentiment) = 'negative' then 1 else 0 end)   as negative_count,
    round(
        sum(case when lower(r.sentiment) = 'positive' then 1 else 0 end)
        / nullif(count(r.review_id), 0) * 100, 1
    )                                                                    as positive_pct
from hotel_dw.core.fact_reviews  as r
join hotel_dw.core.fact_bookings as b on r.booking_id = b.booking_id
join hotel_dw.core.dim_hotels    as h on b.hotel_id   = h.hotel_id
where r.rating is not null
group by 1, 2, 3;

-- -------------------------------------------------------------
-- mart_staff: staff count by hotel, role, shift
-- -------------------------------------------------------------
create or replace table hotel_dw.mart.mart_staff as
select
    h.hotel_id,
    h.hotel_name,
    h.city,
    s.role,
    s.shift,
    count(s.staff_sk)                                            as staff_count
from hotel_dw.core.dim_staff  as s
join hotel_dw.core.dim_hotels as h on s.hotel_id = h.hotel_id
where s.is_current = true
group by 1, 2, 3, 4, 5;
