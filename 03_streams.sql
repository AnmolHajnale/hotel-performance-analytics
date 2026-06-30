-- =============================================================
-- step 3: streams on raw tables (cdc)
-- database: hotel_dw
-- schema:   hotel_dw.raw
-- =============================================================

use role etl_role;
use warehouse hotel_compute_wh;
use schema hotel_dw.raw;

-- -------------------------------------------------------------
-- append_only = true:
-- only captures new inserts from snowpipe
-- does not track updates or deletes (raw is insert-only)
-- offset advances automatically after staging sp consumes it
-- -------------------------------------------------------------

create stream if not exists stream_bookings
    on table hotel_dw.raw.raw_bookings
    append_only = true;

create stream if not exists stream_customers
    on table hotel_dw.raw.raw_customers
    append_only = true;

create stream if not exists stream_hotels
    on table hotel_dw.raw.raw_hotels
    append_only = true;

create stream if not exists stream_staff
    on table hotel_dw.raw.raw_staff
    append_only = true;

create stream if not exists stream_reviews
    on table hotel_dw.raw.raw_reviews
    append_only = true;

create stream if not exists stream_room_rates
    on table hotel_dw.raw.raw_room_rates
    append_only = true;

-- -------------------------------------------------------------
-- check if streams have new data waiting
-- -------------------------------------------------------------
select
    system$stream_has_data('hotel_dw.raw.stream_bookings')   as bookings_ready,
    system$stream_has_data('hotel_dw.raw.stream_customers')  as customers_ready,
    system$stream_has_data('hotel_dw.raw.stream_hotels')     as hotels_ready,
    system$stream_has_data('hotel_dw.raw.stream_staff')      as staff_ready,
    system$stream_has_data('hotel_dw.raw.stream_reviews')    as reviews_ready,
    system$stream_has_data('hotel_dw.raw.stream_room_rates') as room_rates_ready;
