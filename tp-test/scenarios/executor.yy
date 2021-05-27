{

    util = require("util")

    G = {
        c_int = { seq1 = util.seq(),  seq2 = util.seq() },
        c_str = {},
        c_datetime = { range = util.range(1577836800, 1593561599) },
        c_timestamp = { range = util.range(1577836800, 1593561599) },
        c_double = { range = util.range(100) },
        c_decimal = { range = util.range(10) },
        join_hints = {'MERGE_JOIN', 'HASH_JOIN', 'INL_JOIN', 'INL_HASH_JOIN', 'INL_MERGE_JOIN'},
    }

    G.c_int.rand = function() if math.random() < 0.5 then return G.c_int.seq1:rand() else return G.c_int.seq2:rand() end end
    G.c_str.rand = function() return util.quota(random_name()) end
    G.c_datetime.rand = function() return util.quota(G.c_datetime.range:randt()) end
    G.c_timestamp.rand = function() return util.quota(G.c_timestamp.range:randt()) end
    G.c_double.rand = function() return sprintf('%.6f', G.c_double.range:randf()) end
    G.c_decimal.rand = function() return sprintf('%.3f', G.c_decimal.range:randf()) end
    G.rand_join_hint = function() return util.choice(G.join_hints) end

    T = {
        cols = {},
        cur_table = 1,
        cur_col = nil,

        count_ids = {
            c_int = {0, 0},
            c_str = {0, 0},
            c_int_str = {0, 0},
            c_decimal = {0, 0},
        },
        count_partitions = {0, 0},
    }

    T.cols[#T.cols+1] = util.col('c_int', G.c_int.rand)
    T.cols[#T.cols+1] = util.col('c_str', G.c_str.rand)
    T.cols[#T.cols+1] = util.col('c_datetime', G.c_datetime.rand)
    T.cols[#T.cols+1] = util.col('c_timestamp', G.c_timestamp.rand)
    T.cols[#T.cols+1] = util.col('c_double', G.c_double.rand)
    T.cols[#T.cols+1] = util.col('c_decimal', G.c_decimal.rand)
    T.col_int_str = util.col('(c_int, c_str)', function() return sprintf("(%d, %s)", G.c_int.rand(), G.c_str.rand()) end)

    T.rand_col = function() return util.choice(T.cols) end
    T.get_col = function(name)
        for _, c in ipairs(T.cols) do
            if c.name == name then
                return c
            end
        end
        return T.rand_col()
    end

    T.mark_id = function(col)
        T.count_ids[col][T.cur_table] = T.count_ids[col][T.cur_table] + 1
    end
    T.set_partitions = function(n)
        T.count_partitions[T.cur_table] = n
    end
    T.on_create_table_like = function()
        T.count_partitions[T.cur_table] = T.count_partitions[T.cur_table%2+1]
        for _, c in pairs(T.count_ids) do
            c[T.cur_table] = c[T.cur_table%2+1]
        end
    end
    T.one_to_one_predicates = function(fallback)
        ps = {}
        if T.count_ids.c_int[1] > 0 and T.count_ids.c_int[2] > 0 then table.insert(ps, 't1.c_int = t2.c_int') end
        if T.count_ids.c_str[1] > 0 and T.count_ids.c_str[2] > 0 then table.insert(ps, 't1.c_str = t2.c_str') end
        if T.count_ids.c_int_str[1] > 0 and T.count_ids.c_int_str[2] > 0 then table.insert(ps, 't1.c_int = t2.c_int and t1.c_str = t2.c_str') end
        if T.count_ids.c_decimal[1] > 0 and T.count_ids.c_decimal[2] > 0 then table.insert(ps, 't1.c_decimal = t2.c_decimal') end
        if #ps == 0 then table.insert(ps, fallback) end
        return ps
    end

}

# INIT

init:
    drop table if exists t1, t2;
    create_tables;
    insert_data

create_tables:
    create table t1 { T.cur_table = 1 } table_defs;
    create table t2 { T.cur_table = 2 } like t1 { T.on_create_table_like() }
 |  create table t1 { T.cur_table = 1 } table_defs;
    create table t2 { T.cur_table = 2 } table_defs

table_defs:
    [weight=3] (table_cols table_full_keys)
 |  (table_cols, primary_or_unique key ({ local k, t1, t2 = math.random(2), {'c_int', 'c_int_str'}, {'c_int', 'c_int, c_str'}; T.mark_id(t1[k]); print(t2[k]) }) table_part_keys) parted_by_int { T.set_partitions(4) }
 |  [weight=0.5] (table_cols, primary_or_unique key ({ print(util.choice({'c_datetime', 'c_int, c_datetime'})) }) table_part_keys) parted_by_time { T.set_partitions(4) }

primary_or_unique: primary | unique

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
    insert into t2 select * from t1 { G.c_int.seq2._n = G.c_int.seq1._n }
 |  insert into t1 values next_row_t1, next_row_t1, next_row_t1, next_row_t1, next_row_t1;
    insert into t1 values next_row_t1, next_row_t1, next_row_t1, next_row_t1, next_row_t1;
    insert into t2 values next_row_t2, next_row_t2, next_row_t2, next_row_t2, next_row_t2;
    insert into t2 values next_row_t2, next_row_t2, next_row_t2, next_row_t2, next_row_t2

next_row_t1: ({ print(G.c_int.seq1:next()) }, rand_c_str, rand_c_datetime, rand_c_timestamp, rand_c_double, rand_c_decimal)
next_row_t2: ({ print(G.c_int.seq2:next()) }, rand_c_str, rand_c_datetime, rand_c_timestamp, rand_c_double, rand_c_decimal)

# QUERIES

txn:
    reads
 |  begin; writes; reads; commit_or_rollback

t1_or_t2: t1 { T.cur_table = 1 } | t2 { T.cur_table = 2 }
t1_or_t2_partition: t1_or_t1_partition | t2_or_t2_partition
t1_or_t1_partition: t1 { T.cur_table = 1 } | [weight=0.5] { T.cur_table = 1; if T.count_partitions[1] > 0 then printf('t1 partition (p%d)', math.random(0, T.count_partitions[1]-1)) else print('t1') end }
t2_or_t2_partition: t2 { T.cur_table = 2 } | [weight=0.5] { T.cur_table = 2; if T.count_partitions[2] > 0 then printf('t2 partition (p%d)', math.random(0, T.count_partitions[2]-1)) else print('t2') end }
commit_or_rollback: commit | [weight=0.2] rollback
union_or_union_all: union | union all
insert_or_replace: insert | replace
null_or_not: null | not null
all_any_or_some: all | any | some

rand_c_int: { T.get_col('c_int'):pval() }
rand_c_str: { T.get_col('c_str'):pval() }
rand_c_datetime: { T.get_col('c_datetime'):pval() }
rand_c_timestamp: { T.get_col('c_timestamp'):pval() }
rand_c_double: { T.get_col('c_double'):pval() }
rand_c_decimal: { T.get_col('c_decimal'):pval() }
rand_col_val: { T.cur_col:pval() }
rand_col_vals: rand_col_val | rand_col_val, rand_col_vals
rand_row: (rand_c_int, rand_c_str, rand_c_datetime, rand_c_timestamp, rand_c_double, rand_c_decimal)
rand_cmp: < | > | >= | <= | <> | = | !=
rand_logic: [weight=2] and | or
rand_join_type: join | left join | right join
rand_join_hint: | { printf("/*+ %s(t1,t2) */ ", G.rand_join_hint()) }

t_predicates:
    [weight=5] t_predicate1
 |  t_predicate1 rand_logic t_predicates

t_predicate1:
    { T.cur_col = T.rand_col(); print(T.cur_col.name) } = rand_col_val
 |  { T.cur_col = T.rand_col(); print(T.cur_col.name) } in (rand_col_vals)
 |  [weight=0.2] { T.cur_col = T.col_int_str; print(T.cur_col.name) } = rand_col_val
 |  [weight=0.2] { T.cur_col = T.col_int_str; print(T.cur_col.name) } in (rand_col_vals)
 |  { T.cur_col = T.rand_col(); print(T.cur_col.name) } is null_or_not
 |  { T.cur_col = T.rand_col(); print(T.cur_col.name) } rand_cmp rand_col_val
 |  { T.cur_col = T.rand_col(); print(T.cur_col.name) } between { local v1, v2 = T.cur_col:val(), T.cur_col:val(); if v1 > v2 then v1, v2 = v2, v1 end; printf("%v and %v", v1, v2) }

tt_predicates:
    [weight=5] tt_predicate1
 |  tt_predicate1 rand_logic tt_predicates
 |  tt_predicate2 rand_logic tt_predicates

tt_predicate1:
    t1.c_int = t2.c_int
 |  t1.c_int = t2.c_int and { T.cur_col = T.rand_col(); printf("t1.%s", T.cur_col.name) } rand_cmp { printf("t2.%s", T.cur_col.name) }
 |  { T.cur_col = T.rand_col(); printf("t1.%s", T.cur_col.name) } rand_cmp { printf("t2.%s", T.cur_col.name) } and { T.cur_col = T.rand_col(); printf("t1.%s", T.cur_col.name) } rand_cmp { printf("t2.%s", T.cur_col.name) }

tt_predicate2:
    { T.cur_col = T.rand_col(); printf("t%d.%s", math.random(2), T.cur_col.name) } = rand_col_val
 |  { T.cur_col = T.rand_col(); printf("t%d.%s", math.random(2), T.cur_col.name) } in (rand_col_vals)
 |  [weight=0.2] { local t = math.random(2); T.cur_col = T.col_int_str; printf("(t%d.c_int, t%d.c_str)", t, t) } = rand_col_val
 |  [weight=0.2] { local t = math.random(2); T.cur_col = T.col_int_str; printf("(t%d.c_int, t%d.c_str)", t, t) } in (rand_col_vals)
 |  { T.cur_col = T.rand_col(); printf("t%d.%s", math.random(2), T.cur_col.name) } is null_or_not
 |  { T.cur_col = T.rand_col(); printf("t%d.%s", math.random(2), T.cur_col.name) } rand_cmp rand_col_val
 |  { T.cur_col = T.rand_col(); printf("t%d.%s", math.random(2), T.cur_col.name) } between { local v1, v2 = T.cur_col:val(), T.cur_col:val(); if v1 > v2 then v1, v2 = v2, v1 end; printf("%v and %v", v1, v2) }


# WRITE

writes:
    [weight=9] write; writes
 |  write

write:
    common_update
 |  common_insert
 |  common_delete

common_update:
    update t1_or_t2_partition set assignments where t_predicates order by c_int, c_str, c_decimal, c_double limit { print(math.random(2)) }

assignments:
    [weight=9] assignment
 |  assignment, assignments

assignment:
    { T.cur_col = T.rand_col(); print(T.cur_col.name) } = rand_col_val
 |  [weight=0.2] { print(T.rand_col().name) } = null

common_insert:
    insert into t1_or_t2 values rand_row
 |  insert into t1 values next_row_t1
 |  insert into t2 values next_row_t2

common_delete:
    delete from t1_or_t2_partition where c_int = rand_c_int
 |  delete from t1_or_t2_partition where c_double < c_decimal
 |  delete from t1_or_t2_partition where c_str in (rand_c_str, rand_c_str, rand_c_str, rand_c_str, rand_c_str)
 |  delete from t1_or_t2_partition where { print(T.rand_col().name) } is null

# READ

reads:
    [weight=9] read; reads
 |  read; read; read; read; read; read; read; read; read

read:
    select_simple_join
 |  [weight=0.2] (select_simple_join) union_or_union_all (select_simple_join)
 |  select_simple_subquery
 |  [weight=0.2] (select_simple_subquery) union_or_union_all (select_simple_subquery)
 |  select_apply_subquery
 |  [weight=0.2] (select_apply_subquery) union_or_union_all (select_apply_subquery)

select_simple_join:
    [weight=3] select rand_join_hint * from t1, t2 where tt_predicates
 |  select rand_join_hint * from t1 rand_join_type t2 on tt_predicate1
 |  select rand_join_hint * from t1 rand_join_type t2 on tt_predicate1 where tt_predicate2

select_simple_subquery:
    select * from t1 where { T.cur_col = T.rand_col(); print(T.cur_col.name) } sub_cond (select_t2_as_subquery)

sub_cond: < any | = any | > any | <> any | in | not in | > all | < all | <> all

select_t2_as_subquery:
    select { print(T.cur_col.name) } from t2 where t_predicates
 |  select { print(T.cur_col.name) } from t2 where tt_predicates

select_apply_subquery:
    select (select t2.{ c1 = T.rand_col(); print(c1.name) } from t2 where tt_predicate2 order by t2.{ print(c1.name) } limit 1) x from t1 { print("/* force-unordered */") }
 |  select (select t2.{ c1 = T.rand_col(); print(c1.name) } from t2 where t2.{ print(c1.name) } rand_cmp t1.{ print(c1.name) } and t2.c_int = rand_c_int order by t2.{ print(c1.name) } limit 1) x from t1 { print("/* force-unordered */") }
 |  select (select t2.{ c1 = T.rand_col(); print(c1.name) } from t2 where t2.{ print(c1.name) } rand_cmp t1.{ print(c1.name) } and t2.c_int in (rand_c_int, rand_c_int, rand_c_int) order by t2.{ print(c1.name) } limit 1) x from t1 { print("/* force-unordered */") }
