-- =============================================================
-- step 4: staging stored procedure (silver part 1)
-- reads from streams → cleans → deduplicates
-- database: hotel_dw
-- schema:   hotel_dw.staging
-- =============================================================

use role etl_role;
use warehouse hotel_compute_wh;

create or replace procedure hotel_dw.staging.sp_load_staging()
returns string
language sql
execute as caller
as
$$
begin

    -- ---------------------------------------------------------
    -- stg_bookings
    -- ---------------------------------------------------------
    create or replace table hotel_dw.staging.stg_bookings as
    with deduped as (
        select *,
               row_number() over (
                   partition by bookingid
                   order by _loaded_at desc nulls last
               ) as rn
        from hotel_dw.raw.stream_bookings
    )
    select
        try_to_number(bookingid)                                         as booking_id,
        try_to_number(customerid)                                        as customer_id,
        try_to_number(hotelid)                                           as hotel_id,
        try_to_timestamp(checkindate,  'yyyy-mm-dd hh24:mi:ss')          as checkin_date,
        try_to_timestamp(checkoutdate, 'yyyy-mm-dd hh24:mi:ss')          as checkout_date,
        case
            when upper(trim(totalamount)) in ('nan','none','??','','null') then null
            else try_to_decimal(totalamount, 10, 2)
        end                                                              as total_amount,
        try_to_number(stayduration)                                      as stay_duration,
        case upper(trim(highvaluebooking))
            when 'YES' then true
            when 'NO'  then false
            else null
        end                                                              as is_high_value,
        _filename,
        current_timestamp()                                              as _loaded_at
    from deduped
    where rn = 1
      and try_to_number(bookingid) is not null;

    -- ---------------------------------------------------------
    -- stg_customers
    -- ---------------------------------------------------------
    create or replace table hotel_dw.staging.stg_customers as
    with deduped as (
        select *,
               row_number() over (
                   partition by customerid
                   order by _loaded_at desc nulls last
               ) as rn
        from hotel_dw.raw.stream_customers
    ),
    cleaned as (
        select *,
               regexp_replace(
                   split_part(lower(phone), 'x', 1),
                   '[^0-9]', ''
               ) as clean_phone
        from deduped
    )
    select
        try_to_number(customerid)                                        as customer_id,
        initcap(trim(regexp_replace(customername, '[#@$%&]+', '')))      as customer_name,
        case
            when lower(trim(regexp_replace(email, '[#$%&\\s]+', '')))
                 not like '%@%.%' then null
            else lower(trim(regexp_replace(email, '[#$%&\\s]+', '')))
        end                                                              as email,
        case
            when clean_phone is null or clean_phone = ''     then null
            when clean_phone like '001%'                     then '+1' || substr(clean_phone, 4)
            when length(clean_phone) = 10                    then '+1' || clean_phone
            when length(clean_phone) = 11
                 and left(clean_phone, 1) = '1'              then '+' || clean_phone
            else clean_phone
        end                                                              as phone,
        case
            when trim(regexp_replace(city, '[#@$%&]+', ''))
                 in ('??','###','@@@','')                    then null
            else initcap(trim(regexp_replace(city, '[#@$%&]+', '')))
        end                                                              as city,
        current_timestamp()                                              as _loaded_at
    from cleaned
    where rn = 1
      and try_to_number(customerid) is not null;

    -- ---------------------------------------------------------
    -- stg_hotels
    -- ---------------------------------------------------------
    create or replace table hotel_dw.staging.stg_hotels as
    with deduped as (
        select *,
               row_number() over (
                   partition by hotelid
                   order by _loaded_at desc nulls last
               ) as rn
        from hotel_dw.raw.stream_hotels
    )
    select
        try_to_number(hotelid)                                           as hotel_id,
        initcap(trim(regexp_replace(
            replace(regexp_replace(hotelname, '[#@$%&]+', ''), '-', ' '),
            '[,]+', ''
        )))                                                              as hotel_name,
        initcap(trim(regexp_replace(city, '[#@$%&]+', '')))             as city,
        try_to_number(stars)                                             as stars,
        try_to_number(rooms)                                             as rooms,
        current_timestamp()                                              as _loaded_at
    from deduped
    where rn = 1
      and try_to_number(hotelid) is not null;

    -- ---------------------------------------------------------
    -- stg_staff
    -- ---------------------------------------------------------
    create or replace table hotel_dw.staging.stg_staff as
    with deduped as (
        select *,
               row_number() over (
                   partition by staffid
                   order by _loaded_at desc nulls last
               ) as rn
        from hotel_dw.raw.stream_staff
    )
    select
        try_to_number(staffid)                                           as staff_id,
        try_to_number(hotelid)                                           as hotel_id,
        initcap(trim(regexp_replace(staffname, '[#@$%&]+', '')))        as staff_name,
        initcap(trim(regexp_replace(role, '[#@$%&]+', '')))             as role,
        upper(trim(regexp_replace(shift, '[^A-Za-z ]', '')))            as shift,
        current_timestamp()                                              as _loaded_at
    from deduped
    where rn = 1
      and try_to_number(staffid) is not null;

    -- ---------------------------------------------------------
    -- stg_reviews
    -- ---------------------------------------------------------
    create or replace table hotel_dw.staging.stg_reviews as
    with deduped as (
        select *,
               row_number() over (
                   partition by reviewid
                   order by _loaded_at desc nulls last
               ) as rn
        from hotel_dw.raw.stream_reviews
    )
    select
        try_to_number(reviewid)                                          as review_id,
        try_to_number(bookingid)                                         as booking_id,
        try_to_number(customerid)                                        as customer_id,
        case
            when upper(trim(rating)) in ('nan','','null')
                 or rating is null                          then null
            else try_to_number(rating)
        end                                                              as rating,
        initcap(nullif(trim(regexp_replace(comments, '[#@$%&]+', '')),
                       ''))                                              as comments,
        initcap(trim(sentiment))                                         as sentiment,
        current_timestamp()                                              as _loaded_at
    from deduped
    where rn = 1
      and try_to_number(reviewid) is not null;

    -- ---------------------------------------------------------
    -- stg_room_rates
    -- ---------------------------------------------------------
    create or replace table hotel_dw.staging.stg_room_rates as
    with deduped as (
        select *,
               row_number() over (
                   partition by roomrateid
                   order by _loaded_at desc nulls last
               ) as rn
        from hotel_dw.raw.stream_room_rates
    )
    select
        try_to_number(roomrateid)                                        as room_rate_id,
        try_to_number(hotelid)                                           as hotel_id,
        initcap(trim(regexp_replace(roomtype, '[#@$%&]+', '')))         as room_type,
        case
            when upper(trim(price)) in ('nan','??','','null')
                 or price is null                           then null
            else try_to_decimal(price, 10, 2)
        end                                                              as price,
        case
            when upper(trim(discountedprice)) in ('nan','??','','null')
                 or discountedprice is null                 then null
            else try_to_decimal(discountedprice, 10, 2)
        end                                                              as discounted_price,
        case upper(trim(available))
            when 'TRUE'  then true
            when 'FALSE' then false
            else null
        end                                                              as is_available,
        current_timestamp()                                              as _loaded_at
    from deduped
    where rn = 1
      and try_to_number(roomrateid) is not null;

    return 'staging tables loaded successfully from streams';
end;
$$;
