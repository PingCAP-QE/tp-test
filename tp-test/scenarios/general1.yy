{

    local util = require("util")

    T = {
        c_int = { seq = util.seq() },
        c_str = {},
        c_datetime = { range = util.range(1577836800, 1593561599) },
        c_timestamp = { range = util.range(1577836800, 1593561599) },
        c_double = { range = util.range(100) },
        c_decimal = { range = util.range(10) },
    }

    T.c_int.rand = function() return T.c_int.seq:rand() end
    T.c_str.rand = function() return random_name() end
    T.c_datetime.rand = function() return T.c_datetime.range:randt() end
    T.c_timestamp.rand = function() return T.c_timestamp.range:randt() end
    T.c_double.rand = function() return T.c_double.range:randf() end
    T.c_decimal.rand = function() return T.c_decimal.range:randf() end

}

init: drop table if exists t; create_table; insert_data

txn: begin; rand_queries; commit

create_table:
    create table t (
        c_int int,
        c_str varchar(40),
        c_datetime datetime,
        c_timestamp timestamp,
        c_double double,
        c_decimal decimal(12, 6)
        key_primary
        key_c_int
        key_c_str
        key_c_decimal
        key_c_datetime
        key_c_timestamp
    )

key_primary:
 |  , primary key(c_int)
 |  , primary key(c_str)
 |  , primary key(c_str(8))
 |  , primary key(c_int, c_str)
 |  , primary key(c_int, c_str(4))

key_c_int:
 |  , key(c_int)
 |  , unique key(c_int)

key_c_str:
 |  , key(c_str)
 |  , unique key(c_str)

key_c_decimal:
 |  , key(c_decimal)
 |  , unique key(c_decimal)

key_c_datetime:
 |  , key(c_datetime)
 |  , unique key(c_datetime)

key_c_timestamp:
 |  , key(c_timestamp)


insert_data:
    insert into t values next_row, next_row, next_row, next_row, next_row;
    insert into t values next_row, next_row, next_row, next_row, next_row;
    insert into t values next_row, next_row, next_row, next_row, next_row;

next_row: (next_c_int, rand_c_str, rand_c_datetime, rand_c_timestamp, rand_c_double, rand_c_decimal)
rand_row: (rand_c_int, rand_c_str, rand_c_datetime, rand_c_timestamp, rand_c_double, rand_c_decimal)

next_c_int: { print(T.c_int.seq:next()) }
rand_c_int: { print(T.c_int.rand()) }
rand_c_str: { printf("'%s'", T.c_str.rand()) }
rand_c_str_or_null: rand_c_str | [weight=0.2] null
rand_c_datetime: { printf("'%s'", T.c_datetime.rand()) }
rand_c_timestamp: { printf("'%s'", T.c_timestamp.rand()) }
rand_c_double: { printf("%.6f", T.c_double.rand()) }
rand_c_decimal: { printf("%.3f", T.c_decimal.rand()) }

union_or_union_all: union | union all
insert_or_replace: insert | replace

rand_queries:
    rand_query; rand_query; rand_query; rand_query
 |  [weight=9] rand_query; rand_queries

rand_query:
    [weight=0.3] common_select maybe_for_update
 |  [weight=0.2] (common_select maybe_for_update) union_or_union_all (common_select maybe_for_update)
 |  [weight=0.3] agg_select maybe_for_update
 |  [weight=0.2] (agg_select maybe_for_update) union_or_union_all (agg_select maybe_for_update)
 |  [weight=0.5] common_insert
 |  common_update
 |  common_delete
 |  common_update; common_delete; common_select
 |  common_insert; common_delete; common_select
 |  common_delete; common_insert; common_update

maybe_for_update: | for update
maybe_write_limit: | [weight=2] order by c_int, c_str, c_double, c_decimal limit { print(math.random(3)) }

col_list: c_int, c_str, c_double, c_decimal, c_datetime, c_timestamp

common_select:
    select col_list from t where c_int = rand_c_int
 |  select col_list from t where c_int in (rand_c_int, rand_c_int, rand_c_int)
 |  select col_list from t where c_int between { k = T.c_int.rand(); print(k) } and { print(k+3) }
 |  select col_list from t where c_str = rand_c_str
 |  select col_list from t where c_decimal < { local r = T.c_decimal.range; print((r.max-r.min)/2+r.min) }
 |  select col_list from t where c_datetime > rand_c_datetime

agg_select:
    select count(*) from t where c_timestamp between { t = T.c_timestamp.rand(); printf("'%s'", t) } and date_add({ printf("'%s'", t) }, interval 15 day)
 |  select sum(c_int) from t where c_datetime between { t = T.c_datetime.rand(); printf("'%s'", t) } and date_add({ printf("'%s'", t) }, interval 15 day)

common_update:
    update t set c_str = rand_c_str where c_int = rand_c_int
 |  update t set c_double = c_decimal, c_decimal = rand_c_decimal where c_int in (rand_c_int, rand_c_int, rand_c_int)
 |  update t set c_datetime = c_timestamp, c_timestamp = rand_c_timestamp where c_str in (rand_c_str_or_null, rand_c_str_or_null, rand_c_str_or_null)
 |  update t set c_int = c_int + 10, c_str = rand_c_str where c_int in (rand_c_int, { local k = T.c_int.seq:head(); print(k-2) })
 |  update t set c_int = c_int + 5, c_str = rand_c_str_or_null where (c_int, c_str) in ((rand_c_int, rand_c_str), (rand_c_int, rand_c_str), (rand_c_int, rand_c_str))
 |  [weight=0.4] update t set c_datetime = rand_c_datetime, c_timestamp = rand_c_timestamp, c_double = rand_c_double, c_decimal = rand_c_decimal where c_datetime is null maybe_write_limit
 |  [weight=0.4] update t set c_datetime = rand_c_datetime, c_timestamp = rand_c_timestamp, c_double = rand_c_double, c_decimal = rand_c_decimal where c_decimal is null maybe_write_limit

common_insert:
    insert into t values next_row
 |  [weight=0.5] insert_or_replace into t values next_row, next_row, ({ print(T.c_int.seq:head()-1) }, rand_c_str, rand_c_datetime, rand_c_timestamp, rand_c_double, rand_c_decimal)
 |  insert_or_replace into t (c_int, c_str, c_datetime, c_double) values (rand_c_int, rand_c_str, rand_c_datetime, rand_c_double)
 |  insert_or_replace into t (c_int, c_str, c_timestamp, c_decimal) values (next_c_int, rand_c_str, rand_c_timestamp, rand_c_decimal), (rand_c_int, rand_c_str, rand_c_timestamp, rand_c_decimal)
 |  insert into t values rand_row, rand_row, next_row on duplicate key update c_int=values(c_int), c_str=values(c_str), c_double=values(c_double), c_timestamp=values(c_timestamp)
 |  insert into t values rand_row, rand_row, next_row on duplicate key update c_int = c_int + 1, c_str = concat(c_int, ':', c_str)

common_delete:
    delete from t where c_int = rand_c_int
 |  delete from t where c_int in ({ local k = T.c_int.seq:head(); print(k-2) }, rand_c_int) or c_str in (rand_c_str, rand_c_str, rand_c_str, rand_c_str) maybe_write_limit
 |  delete from t where c_str is null
 |  delete from t where c_decimal > c_double/2 maybe_write_limit
 |  [weight=0.8] delete from t where c_timestamp is null or c_double is null maybe_write_limit
