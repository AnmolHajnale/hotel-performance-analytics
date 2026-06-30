-- =============================================================
-- step 5: core dimension tables + scd stored procedure
-- scd type 2: dim_customers, dim_staff, dim_room_rates
-- scd type 1: dim_hotels
-- database: hotel_dw
-- schema:   hotel_dw.core
-- =============================================================

use role etl_role;
use warehouse hotel_compute_wh;
use schema hotel_dw.core;

-- -------------------------------------------------------------
-- dimension table ddls
-- -------------------------------------------------------------

-- scd type 2: customers (tracks city/name changes)
create table if not exists hotel_dw.core.dim_customers (
    customer_sk   int autoincrement primary key,
    customer_id   int not null,
    customer_name varchar,
    email         varchar,
    phone         varchar,
    city          varchar,
    eff_from      timestamp_ntz not null,
    eff_to        timestamp_ntz,
    is_current    boolean default true,
    _loaded_at    timestamp_ntz default current_timestamp()
);

-- scd type 1: hotels (overwrite, no history)
create table if not exists hotel_dw.core.dim_hotels (
    hotel_id   int primary key,
    hotel_name varchar,
    city       varchar,
    stars      int,
    rooms      int,
    _loaded_at timestamp_ntz default current_timestamp()
);

-- scd type 2: staff (tracks role/shift changes)
create table if not exists hotel_dw.core.dim_staff (
    staff_sk   int autoincrement primary key,
    staff_id   int not null,
    hotel_id   int,
    staff_name varchar,
    role       varchar,
    shift      varchar,
    eff_from   timestamp_ntz not null,
    eff_to     timestamp_ntz,
    is_current boolean default true,
    _loaded_at timestamp_ntz default current_timestamp()
);

-- scd type 2: room rates (tracks price changes)
create table if not exists hotel_dw.core.dim_room_rates (
    room_rate_sk     int autoincrement primary key,
    room_rate_id     int not null,
    hotel_id         int,
    room_type        varchar,
    price            decimal(10,2),
    discounted_price decimal(10,2),
    is_available     boolean,
    eff_from         timestamp_ntz not null,
    eff_to           timestamp_ntz,
    is_current       boolean default true,
    _loaded_at       timestamp_ntz default current_timestamp()
);

-- -------------------------------------------------------------
-- stored procedure: load dimensions
-- -------------------------------------------------------------
create or replace procedure hotel_dw.core.sp_load_dimensions()
returns string
language sql
execute as caller
as
$$
begin

    -- ---------------------------------------------------------
    -- dim_hotels: scd type 1 (simple overwrite via merge)
    -- ---------------------------------------------------------
    merge into hotel_dw.core.dim_hotels as target
    using hotel_dw.staging.stg_hotels   as source
        on target.hotel_id = source.hotel_id

    when matched and (
        target.hotel_name is distinct from source.hotel_name or
        target.city       is distinct from source.city       or
        target.stars      is distinct from source.stars      or
        target.rooms      is distinct from source.rooms
    ) then update set
        target.hotel_name = source.hotel_name,
        target.city       = source.city,
        target.stars      = source.stars,
        target.rooms      = source.rooms,
        target._loaded_at = current_timestamp()

    when not matched then insert (
        hotel_id, hotel_name, city, stars, rooms, _loaded_at
    ) values (
        source.hotel_id, source.hotel_name, source.city,
        source.stars, source.rooms, current_timestamp()
    );

    -- ---------------------------------------------------------
    -- dim_customers: scd type 2
    -- step 1: expire old rows where data changed
    -- ---------------------------------------------------------
    update hotel_dw.core.dim_customers as target
    set    eff_to     = current_timestamp(),
           is_current = false
    from   hotel_dw.staging.stg_customers as source
    where  target.customer_id = source.customer_id
      and  target.is_current  = true
      and  (
               target.customer_name is distinct from source.customer_name or
               target.email         is distinct from source.email         or
               target.phone         is distinct from source.phone         or
               target.city          is distinct from source.city
           );

    -- step 2: insert new version for changed + brand new customers
    insert into hotel_dw.core.dim_customers (
        customer_id, customer_name, email, phone, city,
        eff_from, eff_to, is_current, _loaded_at
    )
    select
        source.customer_id,
        source.customer_name,
        source.email,
        source.phone,
        source.city,
        current_timestamp() as eff_from,
        null                as eff_to,
        true                as is_current,
        current_timestamp() as _loaded_at
    from hotel_dw.staging.stg_customers as source
    where not exists (
        select 1
        from hotel_dw.core.dim_customers as existing
        where existing.customer_id   = source.customer_id
          and existing.is_current    = true
          and existing.customer_name = source.customer_name
          and existing.email         = source.email
          and existing.phone         = source.phone
          and existing.city          = source.city
    );

    -- ---------------------------------------------------------
    -- dim_staff: scd type 2
    -- step 1: expire old rows where role/shift changed
    -- ---------------------------------------------------------
    update hotel_dw.core.dim_staff as target
    set    eff_to     = current_timestamp(),
           is_current = false
    from   hotel_dw.staging.stg_staff as source
    where  target.staff_id   = source.staff_id
      and  target.is_current = true
      and  (
               target.role  is distinct from source.role  or
               target.shift is distinct from source.shift
           );

    -- step 2: insert new version
    insert into hotel_dw.core.dim_staff (
        staff_id, hotel_id, staff_name, role, shift,
        eff_from, eff_to, is_current, _loaded_at
    )
    select
        source.staff_id, source.hotel_id, source.staff_name,
        source.role, source.shift,
        current_timestamp(), null, true, current_timestamp()
    from hotel_dw.staging.stg_staff as source
    where not exists (
        select 1
        from hotel_dw.core.dim_staff as existing
        where existing.staff_id   = source.staff_id
          and existing.is_current = true
          and existing.role       = source.role
          and existing.shift      = source.shift
    );

    -- ---------------------------------------------------------
    -- dim_room_rates: scd type 2
    -- step 1: expire old rows where price changed
    -- ---------------------------------------------------------
    update hotel_dw.core.dim_room_rates as target
    set    eff_to     = current_timestamp(),
           is_current = false
    from   hotel_dw.staging.stg_room_rates as source
    where  target.room_rate_id = source.room_rate_id
      and  target.is_current   = true
      and  (
               target.price            is distinct from source.price            or
               target.discounted_price is distinct from source.discounted_price or
               target.is_available     is distinct from source.is_available
           );

    -- step 2: insert new version
    insert into hotel_dw.core.dim_room_rates (
        room_rate_id, hotel_id, room_type, price,
        discounted_price, is_available,
        eff_from, eff_to, is_current, _loaded_at
    )
    select
        source.room_rate_id, source.hotel_id, source.room_type,
        source.price, source.discounted_price, source.is_available,
        current_timestamp(), null, true, current_timestamp()
    from hotel_dw.staging.stg_room_rates as source
    where not exists (
        select 1
        from hotel_dw.core.dim_room_rates as existing
        where existing.room_rate_id     = source.room_rate_id
          and existing.is_current       = true
          and existing.price            is not distinct from source.price
          and existing.discounted_price is not distinct from source.discounted_price
          and existing.is_available     is not distinct from source.is_available
    );

    return 'dimension tables loaded successfully';
end;
$$;
