-- =============================================================
-- step 2: raw tables + snowpipe
-- database: hotel_dw
-- schema:   hotel_dw.raw
-- =============================================================

use role etl_role;
use warehouse hotel_compute_wh;
use database hotel_dw;
use schema raw;

-- -------------------------------------------------------------
-- raw tables: all columns varchar + metadata columns
-- -------------------------------------------------------------
create table if not exists raw_bookings (
    bookingid        varchar,
    customerid       varchar,
    hotelid          varchar,
    checkindate      varchar,
    checkoutdate     varchar,
    totalamount      varchar,
    stayduration     varchar,
    highvaluebooking varchar,
    _loaded_at       timestamp_ntz default current_timestamp(),
    _filename        varchar
);

create table if not exists raw_customers (
    customerid   varchar,
    customername varchar,
    email        varchar,
    phone        varchar,
    city         varchar,
    _loaded_at   timestamp_ntz default current_timestamp(),
    _filename    varchar
);

create table if not exists raw_hotels (
    hotelid    varchar,
    hotelname  varchar,
    city       varchar,
    stars      varchar,
    rooms      varchar,
    _loaded_at timestamp_ntz default current_timestamp(),
    _filename  varchar
);

create table if not exists raw_staff (
    staffid    varchar,
    hotelid    varchar,
    staffname  varchar,
    role       varchar,
    shift      varchar,
    _loaded_at timestamp_ntz default current_timestamp(),
    _filename  varchar
);

create table if not exists raw_reviews (
    reviewid   varchar,
    bookingid  varchar,
    customerid varchar,
    rating     varchar,
    comments   varchar,
    sentiment  varchar,
    _loaded_at timestamp_ntz default current_timestamp(),
    _filename  varchar
);

create table if not exists raw_room_rates (
    roomrateid      varchar,
    hotelid         varchar,
    roomtype        varchar,
    price           varchar,
    available       varchar,
    discountedprice varchar,
    _loaded_at      timestamp_ntz default current_timestamp(),
    _filename       varchar
);

-- -------------------------------------------------------------
-- external stage: points to s3 processed folder
-- -------------------------------------------------------------
create stage if not exists hotel_s3_stage
    storage_integration = s3_hotel_integration
    url                 = 's3://hospitality-raw-bucket/processed/'
    file_format         = (
        type                         = csv
        field_optionally_enclosed_by = '"'
        skip_header                  = 1
        null_if                      = ('', 'null', 'none', 'nan', '??')
        empty_field_as_null          = true
    );

-- -------------------------------------------------------------
-- snowpipe: one per table, auto ingest on s3 file arrival
-- -------------------------------------------------------------
create pipe if not exists pipe_bookings
    auto_ingest = true
    comment     = 'loads bookings csv from s3 processed/bookings/'
as
copy into raw_bookings (
    bookingid, customerid, hotelid,
    checkindate, checkoutdate, totalamount,
    stayduration, highvaluebooking, _filename
)
from (
    select
        $1, $2, $3, $4, $5, $6, $7, $8,
        metadata$filename
    from @hotel_s3_stage/bookings/
);

create pipe if not exists pipe_customers
    auto_ingest = true
    comment     = 'loads customers csv from s3 processed/customers/'
as
copy into raw_customers (
    customerid, customername, email, phone, city, _filename
)
from (
    select $1, $2, $3, $4, $5, metadata$filename
    from @hotel_s3_stage/customers/
);

create pipe if not exists pipe_hotels
    auto_ingest = true
    comment     = 'loads hotels csv from s3 processed/hotels/'
as
copy into raw_hotels (
    hotelid, hotelname, city, stars, rooms, _filename
)
from (
    select $1, $2, $3, $4, $5, metadata$filename
    from @hotel_s3_stage/hotels/
);

create pipe if not exists pipe_staff
    auto_ingest = true
    comment     = 'loads staff csv from s3 processed/staff/'
as
copy into raw_staff (
    staffid, hotelid, staffname, role, shift, _filename
)
from (
    select $1, $2, $3, $4, $5, metadata$filename
    from @hotel_s3_stage/staff/
);

create pipe if not exists pipe_reviews
    auto_ingest = true
    comment     = 'loads reviews json from s3 processed/reviews/'
as
copy into raw_reviews (
    reviewid, bookingid, customerid, rating, comments, sentiment, _filename
)
from (
    select $1, $2, $3, $4, $5, $6, metadata$filename
    from @hotel_s3_stage/reviews/
);

create pipe if not exists pipe_room_rates
    auto_ingest = true
    comment     = 'loads room rates json from s3 processed/room_rates/'
as
copy into raw_room_rates (
    roomrateid, hotelid, roomtype, price, available, discountedprice, _filename
)
from (
    select $1, $2, $3, $4, $5, $6, metadata$filename
    from @hotel_s3_stage/room_rates/
);

-- -------------------------------------------------------------
-- after creating pipes: get sqs arn for each pipe
-- paste sqs arn into aws s3 bucket event notification
-- -------------------------------------------------------------
show pipes;
