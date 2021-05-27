{

    util = require("util")

    T = {
        c_int = { seq1 = util.seq(), seq2 = util.seq() },
        c_str = {},
        c_datetime = { range = util.range(1577836800, 1593561599) },
        c_timestamp = { range = util.range(1577836800, 1593561599) },
        c_double = { range = util.range(100) },
        c_decimal = { range = util.range(10) },

        cols = {'c_int', 'c_int', 'c_int', 'c_str', 'c_str', 'c_datetime', 'c_timestamp', 'c_double', 'c_decimal'},
        hints = {'MERGE_JOIN', 'INL_JOIN', 'INL_HASH_JOIN', 'INL_MERGE_JOIN', 'HASH_JOIN'},

        current_col = 'c_int',
        current_table = 1,
        count_ids = {
            c_int = {0, 0},
            c_str = {0, 0},
            c_int_str = {0, 0},
            c_decimal = {0, 0},
        },
        count_parted = 0,
        count_create_like = 0,
    }

    T.c_int.rand_head = function() return util.choice({T.c_int.seq1, T.c_int.seq1}):head() end
    T.c_str.rand = function() return random_name() end
    T.c_datetime.rand = function() return T.c_datetime.range:randt() end
    T.c_timestamp.rand = function() return T.c_timestamp.range:randt() end
    T.c_double.rand = function() return T.c_double.range:randf() end
    T.c_decimal.rand = function() return T.c_decimal.range:randf() end
    T.rand_col = function() return util.choice(T.cols) end
    T.rand_hint = function() return util.choice(T.hints) end

    T.mark_id = function(col) T.count_ids[col][T.current_table] = T.count_ids[col][T.current_table] + 1 end
    T.mark_dup = function()
        for _, c in pairs(T.count_ids) do
            c[T.current_table] = c[T.current_table%2+1]
        end
    end
    T.one_to_one_predicates = function()
        ps = {}
        if T.count_ids.c_int[1] > 0 and T.count_ids.c_int[2] > 0 then table.insert(ps, 't1.c_int = t2.c_int') end
        if T.count_ids.c_str[1] > 0 and T.count_ids.c_str[2] > 0 then table.insert(ps, 't1.c_str = t2.c_str') end
        if T.count_ids.c_int_str[1] > 0 and T.count_ids.c_int_str[2] > 0 then table.insert(ps, 't1.c_int = t2.c_int and t1.c_str = t2.c_str') end
        if T.count_ids.c_decimal[1] > 0 and T.count_ids.c_decimal[2] > 0 then table.insert(ps, 't1.c_decimal = t2.c_decimal') end
        if #ps == 0 then table.insert(ps, '1 = 0') end
        return ps
    end
    T.both_parted = function() return T.count_parted + T.count_create_like == 2 end
}

init: drop table if exists t1, t2; create_table; insert_data

txn: begin; rand_queries; commit

create_table:
    create table t1 { T.current_table = 1 } table_defs;
    create table t2 { T.current_table = 2 } like t1 { T.count_create_like = T.count_create_like + 1; T.mark_dup() }
 |  create table t1 { T.current_table = 1 } table_defs;
    create table t2 { T.current_table = 2 } table_defs

key_primary:
 |  , primary key(c_int) { T.mark_id('c_int') }
 |  , primary key(c_str) { T.mark_id('c_str') }
 |  , primary key(c_str(8)) { T.mark_id('c_str') }
 |  , primary key(c_int, c_str) { T.mark_id('c_int_str') }
 |  , primary key(c_int, c_str(4)) { T.mark_id('c_int_str') }

key_c_int_part: | , key(c_int)
key_c_int: [weight=2] key_c_int_part | , unique key(c_int) { T.mark_id('c_int') }
key_c_str_part: | , key(c_str)
key_c_str: [weight=2] key_c_str_part | , unique key(c_str) { T.mark_id('c_str') }
key_c_decimal_part: | , key(c_decimal)
key_c_decimal: [weight=2] key_c_decimal_part | , unique key(c_decimal) { T.mark_id('c_decimal') }
key_c_datetime_part: | , key(c_datetime)
key_c_datetime: [weight=2] key_c_datetime_part | , unique key(c_datetime)
key_c_timestamp_part: | , key(c_timestamp)
key_c_timestamp: [weight=2] key_c_timestamp_part | , unique key(c_timestamp)

table_defs:
    (table_cols table_full_keys)
 |  [omit] (table_cols, primary key ({ local k, t1, t2 = math.random(2), {'c_int', 'c_int_str'}, {'c_int', 'c_int, c_str'}; T.mark_id(t1[k]); print(t2[k]) }) table_part_keys) parted_by_int { T.count_parted = T.count_parted + 1 }
 |  [omit] (table_cols, primary key ({ print(util.choice({'c_datetime', 'c_int, c_datetime'})) }) table_part_keys) parted_by_time { T.count_parted = T.count_parted + 1 }

table_cols:
    c_int int,
    c_str varchar(40),
    c_datetime datetime,
    c_timestamp timestamp,
    c_double double,
    c_decimal decimal(12, 6)

table_full_keys:
    key_primary
    key_c_int
    key_c_str
    key_c_decimal
    key_c_datetime
    key_c_timestamp

table_part_keys:
    key_c_int_part
    key_c_str_part
    key_c_decimal_part
    key_c_datetime_part
    key_c_timestamp_part

parted_by_int:
    partition by hash (c_int) partitions 4
 |  partition by range (c_int) (
    partition p0 values less than (10),
    partition p1 values less than (20),
    partition p2 values less than (30),
    partition p3 values less than maxvalue)

parted_by_time:
    partition by range (to_days(c_datetime)) (
    partition p0 values less than (to_days('2020-02-01')),
    partition p1 values less than (to_days('2020-04-01')),
    partition p2 values less than (to_days('2020-06-01')),
    partition p3 values less than maxvalue)

insert_data:
    insert into t1 values next_row_t1, next_row_t1, next_row_t1, next_row_t1, next_row_t1;
    insert into t1 values next_row_t1, next_row_t1, next_row_t1, next_row_t1, next_row_t1;
    insert into t2 select * from t1 { T.c_int.seq2._n = T.c_int.seq1._n }
 |  insert into t1 values next_row_t1, next_row_t1, next_row_t1, next_row_t1, next_row_t1;
    insert into t1 values next_row_t1, next_row_t1, next_row_t1, next_row_t1, next_row_t1;
    insert into t2 values next_row_t2, next_row_t2, next_row_t2, next_row_t2, next_row_t2;
    insert into t2 values next_row_t2, next_row_t2, next_row_t2, next_row_t2, next_row_t2

next_row_t1: (next_c_int_t1, rand_c_str, rand_c_datetime, rand_c_timestamp, rand_c_double, rand_c_decimal)
next_row_t2: (next_c_int_t2, rand_c_str, rand_c_datetime, rand_c_timestamp, rand_c_double, rand_c_decimal)
rand_row: (rand_c_int, rand_c_str, rand_c_datetime, rand_c_timestamp, rand_c_double, rand_c_decimal)

next_c_int_t1: { print(T.c_int.seq1:next()) }
next_c_int_t2: { print(T.c_int.seq2:next()) }
rand_c_int_t1: { print(T.c_int.seq1:rand()) }
rand_c_int_t2: { print(T.c_int.seq2:rand()) }
rand_c_int: { if math.random() < 0.5 then print(T.c_int.seq1:rand()) else print(T.c_int.seq2:rand()) end }
rand_c_str: { printf("'%s'", T.c_str.rand()) }
rand_c_str_or_null: rand_c_str | [weight=0.2] null
rand_c_datetime: { printf("'%s'", T.c_datetime.rand()) }
rand_c_timestamp: { printf("'%s'", T.c_timestamp.rand()) }
rand_c_double: { printf("%.6f", T.c_double.rand()) }
rand_c_decimal: { printf("%.3f", T.c_decimal.rand()) }

union_or_union_all: union | union all
insert_or_replace: insert | replace
null_or_not: is null | is not null
all_or_any_or_some: all | any | some

t1_or_t1_partition: t1 | { if T.both_parted() then printf('t1 partition (p%d)', math.random(0, 3)) else print('t1') end }
t2_or_t2_partition: t2 | { if T.both_parted() then printf('t2 partition (p%d)', math.random(0, 3)) else print('t2') end }
tt_or_tt_partition: t1, t2 | { local p = math.random(0, 3); if T.both_parted() then printf('t1 partition (p%d), t2 partition (p%d)', p, p) else print('t1, t2') end }

rand_queries:
    rand_query; rand_query; rand_query; rand_query
 |  [weight=9] rand_query; rand_queries

rand_query:
    select_simple_join maybe_for_update
 |  (select_simple_join maybe_for_update) union_or_union_all (select_simple_join maybe_for_update)
 |  select_simple_subquery maybe_for_update
 |  select_apply_point_get
 |  update_multi_tables
 |  delete_multi_tables
 |  [weight=0.5] common_insert_t1
 |  [weight=0.5] common_insert_t2
 |  common_update
 |  common_delete


rand_table: t1_or_t1_partition | t2_or_t2_partition
rand_cmp: < | > | >= | <= | <> | = | !=
rand_logic: and | or
rand_hint: | { printf("/*+ %s(t1,t2) */ ", T.rand_hint()) }
rand_join: join | left join | right join

maybe_for_update: | [weight=0.4] for update
maybe_write_limit: | [weight=2] order by c_int, c_str, c_double, c_decimal limit { print(math.random(3)) }

predicates:
    predicate1 rand_logic predicates
 |  predicate1
 |  predicate2

predicate_one_to_one: { print(util.choice(T.one_to_one_predicates())) }

predicate1:
    { c = T.rand_col(); printf("t1.%s", c) } rand_cmp { printf("t2.%s", c) }
 |  t1.c_int = t2.c_int
 |  t1.c_str rand_cmp t2.c_str
 |  t1.c_int = t2.c_int and t1.c_str rand_cmp t2.c_str

predicate2:
    { printf("t%d.c_int", math.random(2)) } = rand_c_int_t1
 |  { printf("t%d.c_int", math.random(2)) } in (rand_c_int_t1, rand_c_int_t2, rand_c_int_t1)
 |  { printf("t%d.c_str", math.random(2)) } = rand_c_str
 |  { printf("t%d.c_str", math.random(2)) } in (rand_c_str, rand_c_str, rand_c_str)
 |  { printf("t%d.%s", math.random(2), T.rand_col()) } null_or_not


select_simple_join:
    [weight=3] select rand_hint * from t1, t2 where predicates
 |  select rand_hint * from t1 rand_join t2 on predicate1
 |  select rand_hint * from t1 rand_join t2 on predicate1 where predicates

select_simple_subquery:
    select * from t1 where { T.current_col = T.rand_col(); print(T.current_col) } in (subquery_for_t1)
 |  select * from t1 where { T.current_col = T.rand_col(); print(T.current_col) } rand_cmp all_or_any_or_some (subquery_for_t1)

select_apply_point_get:
    select (select t2.{ c = T.rand_col(); print(c) } from t2 where predicates order by t2.{ print(c) } limit 1 maybe_for_update) x from t1 { print("/* force-unordered */") }
 |  select (select t2.{ c = T.rand_col(); print(c) } from t2 where t2.{ print(c) } rand_cmp t1.{ print(c) } and t2.c_int = rand_c_int order by t2.{ print(c) } limit 1 maybe_for_update) x from t1 { print("/* force-unordered */") }
 |  select (select t2.{ c = T.rand_col(); print(c) } from t2 where t2.{ print(c) } rand_cmp t1.{ print(c) } and t2.c_int in (rand_c_int, rand_c_int, rand_c_int) order by t2.{ print(c) } limit 1 maybe_for_update) x from t1 { print("/* force-unordered */") }

subquery_for_t1:
    select_from_t2_only
 |  select_from_t2_with_t1

select_from_t2_only:
    select { print(T.current_col) } from t2 where c_int = rand_c_int
 |  select { print(T.current_col) } from t2 where c_int in (rand_c_int, rand_c_int, rand_c_int)
 |  select { print(T.current_col) } from t2 where c_int between { k = T.c_int.seq2:rand(); print(k) } and { print(k+3) }
 |  select { print(T.current_col) } from t2 where c_str = rand_c_str
 |  select { print(T.current_col) } from t2 where c_decimal < { local r = T.c_decimal.range; print((r.max-r.min)/2+r.min) }
 |  select { print(T.current_col) } from t2 where c_datetime > rand_c_datetime

select_from_t2_with_t1:
    select { print(T.current_col) } from t2 where predicates

rand_assignments:
    rand_assignment
 |  rand_assignment, rand_assignments

rand_assignment:
    { local c = T.rand_col(); printf("t1.%s = t2.%s", c, c) }
 |  { printf("t%d.c_int", math.random(2)) } = rand_c_int
 |  { printf("t%d.c_str", math.random(2)) } = rand_c_str
 |  { printf("t%d.c_decimal", math.random(2)) } = rand_c_decimal
 |  { printf("t%d.c_timestamp", math.random(2)) } = rand_c_timestamp

update_multi_tables:
    update rand_hint tt_or_tt_partition set rand_assignments where predicate_one_to_one and (predicates)
 |  [omit] update tt_or_tt_partition set { local c = T.rand_col(); printf("t1.%s = t2.%s, t2.%s = t1.%s", c, c, c, c) } where predicate_one_to_one and (predicates)

delete_multi_tables:
    delete rand_hint t1, t2 from tt_or_tt_partition where predicates
 |  delete rand_hint t1 from tt_or_tt_partition where predicates
 |  delete rand_hint t2 from tt_or_tt_partition where predicates

common_insert_t1:
    insert into t1 values next_row_t1
 |  [weight=0.5] insert_or_replace into t1 values next_row_t1, next_row_t1, ({ print(T.c_int.seq1:head()-1) }, rand_c_str, rand_c_datetime, rand_c_timestamp, rand_c_double, rand_c_decimal)
 |  insert_or_replace into t1 (c_int, c_str, c_datetime, c_double) values (rand_c_int_t1, rand_c_str, rand_c_datetime, rand_c_double)
 |  insert_or_replace into t1 (c_int, c_str, c_timestamp, c_decimal) values (next_c_int_t1, rand_c_str, rand_c_timestamp, rand_c_decimal), (rand_c_int_t1, rand_c_str, rand_c_timestamp, rand_c_decimal)
 |  insert into t1 values rand_row, rand_row, next_row_t1 on duplicate key update c_int=values(c_int), c_str=values(c_str), c_double=values(c_double), c_timestamp=values(c_timestamp)
 |  insert into t1 values rand_row, rand_row, next_row_t1 on duplicate key update c_int = c_int + 1, c_str = concat(c_int, ':', c_str)

common_insert_t2:
    insert into t2 values next_row_t2
 |  [weight=0.5] insert_or_replace into t2 values next_row_t2, next_row_t2, ({ print(T.c_int.seq2:head()-1) }, rand_c_str, rand_c_datetime, rand_c_timestamp, rand_c_double, rand_c_decimal)
 |  insert_or_replace into t2 (c_int, c_str, c_datetime, c_double) values (rand_c_int_t2, rand_c_str, rand_c_datetime, rand_c_double)
 |  insert_or_replace into t2 (c_int, c_str, c_timestamp, c_decimal) values (next_c_int_t2, rand_c_str, rand_c_timestamp, rand_c_decimal), (rand_c_int_t2, rand_c_str, rand_c_timestamp, rand_c_decimal)
 |  insert into t2 values rand_row, rand_row, next_row_t2 on duplicate key update c_int=values(c_int), c_str=values(c_str), c_double=values(c_double), c_timestamp=values(c_timestamp)
 |  insert into t2 values rand_row, rand_row, next_row_t2 on duplicate key update c_int = c_int + 1, c_str = concat(c_int, ':', c_str)

common_update:
    update rand_table set c_str = rand_c_str where c_int = rand_c_int
 |  update rand_table set c_double = c_decimal, c_decimal = rand_c_decimal where c_int in (rand_c_int, rand_c_int, rand_c_int)
 |  update rand_table set c_datetime = c_timestamp, c_timestamp = rand_c_timestamp where c_str in (rand_c_str_or_null, rand_c_str_or_null, rand_c_str_or_null)
 |  update rand_table set c_int = c_int + 10, c_str = rand_c_str where c_int in (rand_c_int, { local k = T.c_int.rand_head(); print(k-math.random(3)) })
 |  update rand_table set c_int = c_int + 5, c_str = rand_c_str_or_null where (c_int, c_str) in ((rand_c_int, rand_c_str), (rand_c_int, rand_c_str), (rand_c_int, rand_c_str))
 |  [weight=0.4] update rand_table set c_datetime = rand_c_datetime, c_timestamp = rand_c_timestamp, c_double = rand_c_double, c_decimal = rand_c_decimal where c_datetime is null maybe_write_limit
 |  [weight=0.4] update rand_table set c_datetime = rand_c_datetime, c_timestamp = rand_c_timestamp, c_double = rand_c_double, c_decimal = rand_c_decimal where c_decimal is null maybe_write_limit

common_delete:
    delete from rand_table where c_int = rand_c_int
 |  delete from rand_table where c_int in ({ local k = T.c_int.rand_head(); print(k-math.random(3)) }, rand_c_int) or c_str in (rand_c_str, rand_c_str, rand_c_str, rand_c_str) maybe_write_limit
 |  delete from rand_table where c_str is null
 |  delete from rand_table where c_decimal > c_double/2 maybe_write_limit
 |  [weight=0.8] delete from rand_table where c_timestamp is null or c_double is null maybe_write_limit
