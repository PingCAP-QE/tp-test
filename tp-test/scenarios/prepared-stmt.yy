{

    util = require("util")

    G = {
        c_int = { seq = util.seq() },
        c_str = {},
        c_datetime = { range = util.range(1577836800, 1593561599) },
        c_timestamp = { range = util.range(1577836800, 1593561599) },
        c_double = { range = util.range(100) },
        c_decimal = { range = util.range(10) },
    }

    G.c_int.rand = function() return G.c_int.seq:rand() end
    G.c_str.rand = function() return util.quota(random_name()) end
    G.c_datetime.rand = function() return util.quota(G.c_datetime.range:randt()) end
    G.c_timestamp.rand = function() return util.quota(G.c_timestamp.range:randt()) end
    G.c_double.rand = function() return sprintf('%.6f', G.c_double.range:randf()) end
    G.c_decimal.rand = function() return sprintf('%.3f', G.c_decimal.range:randf()) end

    T = {
        cols = {},
        cur_col = nil,
    }

    T.cols[#T.cols+1] = util.col('c_int', G.c_int.rand)
    T.cols[#T.cols+1] = util.col('c_str', G.c_str.rand)
    T.cols[#T.cols+1] = util.col('c_datetime', G.c_datetime.rand)
    T.cols[#T.cols+1] = util.col('c_timestamp', G.c_timestamp.rand)
    T.cols[#T.cols+1] = util.col('c_double', G.c_double.rand)
    T.cols[#T.cols+1] = util.col('c_decimal', G.c_decimal.rand)

    T.col_int_str = util.col('(c_int, c_str)', function() return sprintf("(%d, %s)", G.c_int.rand(), G.c_str.rand()) end)

    T.rand_col = function()
        return util.choice(T.cols)
    end
    T.get_col = function(name)
        for _, c in ipairs(T.cols) do
            if c.name == name then
                return c
            end
        end
        return T.rand_col()
    end

}

init: create_table; insert_data; prepare_stmts

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
 |  , primary key(c_str, c_int)
 |  , primary key(c_str(4), c_int)

key_c_int:
 |  , key(c_int)
 |  , unique key(c_int)

key_c_str:
 |  , key(c_str)
 |  , unique key(c_str)

key_c_decimal:
 |  , key(c_decimal)
 |  [weight=0.5] , unique key(c_decimal)

key_c_datetime:
 |  , key(c_datetime)
 |  [weight=0.2] , unique key(c_datetime)

key_c_timestamp:
 |  , key(c_timestamp)
 |  [weight=0.2] , unique key(c_timestamp)


insert_data:
    insert into t values next_row, next_row, next_row, next_row, next_row;
    insert into t values next_row, next_row, next_row, next_row, next_row

next_row: (next_c_int, rand_c_str, rand_c_datetime, rand_c_timestamp, rand_c_double, rand_c_decimal)
rand_row: (rand_c_int, rand_c_str, rand_c_datetime, rand_c_timestamp, rand_c_double, rand_c_decimal)

next_c_int: { print(G.c_int.seq:next()) }
rand_c_int: { T.get_col('c_int'):pval() }
rand_c_str: { T.get_col('c_str'):pval() }
rand_c_datetime: { T.get_col('c_datetime'):pval() }
rand_c_timestamp: { T.get_col('c_timestamp'):pval() }
rand_c_double: { T.get_col('c_double'):pval() }
rand_c_decimal: { T.get_col('c_decimal'):pval() }
rand_col_val: { T.cur_col:pval() }
rand_col_vals: rand_col_val | rand_col_val, rand_col_vals

prepare_stmts:
    prepare s1 from 'select c_int, c_str, c_double, c_decimal, c_datetime, c_timestamp from t where c_int = ?';
    prepare s2 from 'select c_int, c_str, c_double, c_decimal, c_datetime, c_timestamp from t where c_str = ?';
    prepare s3 from 'select c_int, c_str, c_double, c_decimal, c_datetime, c_timestamp from t where (c_int, c_str) = (?, ?)';
    prepare s4 from 'select c_int, c_str, c_double, c_decimal, c_datetime, c_timestamp from t where c_int in (?, ?, ?)';
    prepare s5 from 'select c_int, c_str, c_double, c_decimal, c_datetime, c_timestamp from t where c_str in (?, ?, ?)';
    prepare s6 from 'select c_int, c_str, c_double, c_decimal, c_datetime, c_timestamp from t where (c_int, c_str) in ((?, ?), (?, ?), (?, ?))';
    prepare s7 from 'select c_int, c_str, c_double, c_decimal, c_datetime, c_timestamp from t where c_decimal < ?';
    prepare s8 from 'select c_int, c_str, c_double, c_decimal, c_datetime, c_timestamp from t where c_datetime between ? and ?';
    prepare s9 from 'select count(c_int) from t where c_int >= ? and c_int < ?';
    prepare u1 from 'update t set c_str = ? where c_int = ?';
    prepare u2 from 'update t set c_decimal = c_decimal * ? where c_int in (?, ?, ?)';
    prepare u3 from 'update t set c_int = c_int + ? where c_datetime between ? and ? order by c_int, c_str, c_decimal, c_double limit 2';
    prepare i1 from 'insert into t values (?, ?, ?, ?, ?, ?)';
    prepare i2 from 'insert into t values (?, ?, ?, ?, ?, ?), (?, ?, ?, ?, ?, ?) on duplicate key update c_int=values(c_int), c_str=values(c_str), c_double=values(c_double), c_timestamp=values(c_timestamp)';
    prepare d1 from 'delete from t where c_int = ?';
    prepare d2 from 'delete from t where c_int in (?, ?, ?)';
    prepare d3 from 'delete from t where c_decimal > ? order by c_int, c_str, c_decimal, c_double limit ?';
    prepare s from 'select 1'

execute_rand_stmt:
    [weight=2] execute_select_stmt
 |  execute_update_stmt
 |  execute_insert_stmt
 |  execute_delete_stmt

execute_select_stmt:
    set @v1 = rand_c_int;
    execute s1 using @v1
 |  set @v1 = rand_c_str;
    execute s2 using @v1
 |  set @v1 = rand_c_int, @v2 = rand_c_str;
    execute s3 using @v1, @v2
 |  set @v1 = rand_c_int, @v2 = rand_c_int, @v3 = rand_c_int;
    execute s4 using @v1, @v2, @v3
 |  set @v1 = rand_c_str, @v2 = rand_c_str, @v3 = rand_c_str;
    execute s5 using @v1, @v2, @v3
 |  set @v1 = rand_c_int, @v2 = rand_c_int, @v3 = rand_c_int, @u1 = rand_c_str, @u2 = rand_c_str, @u3 = rand_c_str;
    execute s6 using @v1, @u1, @v2, @u2, @v3, @u3
 |  set @v1 = rand_c_decimal;
    execute s7 using @v1
 |  set { local v1, v2 = G.c_datetime.rand(), G.c_datetime.rand(); if v1 > v2 then v1, v2 = v2, v1 end; printf('@v1 = %s, @v2 = %s', v1, v2) };
    execute s8 using @v1, @v2
 |  set { local v1, v2 = G.c_int.rand(), G.c_int.rand(); if v1 > v2 then v1, v2 = v2, v1 end; printf('@v1 = %d, @v2 = %d', v1, v2) };
    execute s9 using @v1, @v2

execute_update_stmt:
    set @v1 = rand_c_str, @v2 = rand_c_int;
    execute u1 using @v1, @v2
 |  set @v1 = { print(util.choice({math.random(), -1, 0.5, 2})) }, @v2 = rand_c_int, @v3 = rand_c_int, @v4 = rand_c_int;
    execute u2 using @v1, @v2, @v3, @v4
 |  set @v1 = { print(math.random(5, 10)) }, { local v1, v2 = G.c_datetime.rand(), G.c_datetime.rand(); if v1 > v2 then v1, v2 = v2, v1 end; printf('@v2 = %s, @v3 = %s', v1, v2) };
    execute u3 using @v1, @v2, @v3

execute_insert_stmt:
    set @v11 = next_c_int, @v12 = rand_c_str, @v13 = rand_c_datetime, @v14 = rand_c_timestamp, @v15 = rand_c_double, @v16 = rand_c_decimal;
    execute i1 using @v11, @v12, @v13, @v14, @v15, @v16
 |  set @v11 = rand_c_int, @v12 = rand_c_str, @v13 = rand_c_datetime, @v14 = rand_c_timestamp, @v15 = rand_c_double, @v16 = rand_c_decimal;
    set @v21 = rand_c_int, @v22 = rand_c_str, @v23 = rand_c_datetime, @v24 = rand_c_timestamp, @v25 = rand_c_double, @v26 = rand_c_decimal;
    execute i2 using @v11, @v12, @v13, @v14, @v15, @v16, @v21, @v22, @v23, @v24, @v25, @v26

execute_delete_stmt:
    set @v1 = rand_c_int;
    execute d1 using @v1
 |  set @v1 = rand_c_int, @v2 = rand_c_int, @v3 = rand_c_int;
    execute d2 using @v1, @v2, @v3
 |  set @v1 = rand_c_decimal, @v2 = { print(math.random(3)) };
    execute d3 using @v1, @v2

rand_queries:
    rand_query; rand_query; rand_query; rand_query; rand_query; rand_query; rand_query
 |  [weight=10] rand_query; rand_queries

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
 |  [weight=12] execute_rand_stmt

rand_cmp: < | > | >= | <= | <> | = | !=
rand_logic: or | and
rand_arithmetic: + | - | * | /
rand_strfunc: upper | lower | reverse | to_base64

is_null_or_not: is null | is not null
union_or_union_all: union | union all
insert_or_replace: insert | replace

maybe_for_update: | for update
maybe_write_limit: | [weight=2] order by c_int, c_str, c_decimal, c_double limit { print(math.random(3)) }

selected_cols: c_int, c_str, c_double, c_decimal, c_datetime, c_timestamp

predicates: [weight=2] predicate | predicate rand_logic predicates

predicate:
    { T.cur_col = T.rand_col(); print(T.cur_col.name) } = rand_col_val
 |  { T.cur_col = T.rand_col(); print(T.cur_col.name) } in (rand_col_vals)
 |  { T.cur_col = T.col_int_str; print(T.cur_col.name) } = rand_col_val
 |  { T.cur_col = T.col_int_str; print(T.cur_col.name) } in (rand_col_vals)
 |  { T.cur_col = T.rand_col(); print(T.cur_col.name) } rand_cmp rand_col_val
 |  { T.cur_col = T.rand_col(); print(T.cur_col.name) } between { local v1, v2 = T.cur_col:val(), T.cur_col:val(); if v1 > v2 then v1, v2 = v2, v1 end; printf("%v and %v", v1, v2) }
 |  { print(util.choice({'c_decimal', 'c_double', 'c_datetime', 'c_timestamp'})) } is_null_or_not

common_select:
    select selected_cols from t where predicate
 |  select selected_cols from t where predicates

agg_select:
    select count(*) from t where predicates
 |  select sum(c_int) from t where predicates

assignments: [weight=3] assignment | assignment, assignments

assignment:
    { T.cur_col = T.rand_col(); print(T.cur_col.name) } = rand_col_val
 |  [weight=0.3] { T.cur_col = T.get_col(util.choice({'c_int', 'c_decimal', 'c_double'})); print(T.cur_col.name) } = { print(T.cur_col.name) } rand_arithmetic { T.cur_col:pval() }
 |  [weight=0.1] c_str = rand_strfunc(c_str)

common_update:
    update t set assignments where predicates maybe_write_limit

rows_to_ins: [weight=4] row_to_ins | row_to_ins, rows_to_ins

row_to_ins:
    next_row
 |  [weight=0.4] rand_row
 |  [weight=0.4] ({ print(G.c_int.seq:head()-math.random(3)) }, rand_c_str, rand_c_datetime, rand_c_timestamp, rand_c_double, rand_c_decimal)

on_dup_assignments: [weight=3] on_dup_assignment | on_dup_assignment, on_dup_assignments

on_dup_assignment:
    assignment
 |  { T.cur_col = T.rand_col(); print(T.cur_col.name) } = values({ print(T.cur_col.name) })

common_insert:
    insert_or_replace into t values rows_to_ins
 |  insert_or_replace into t (c_int, c_str, c_datetime, c_double) values (rand_c_int, rand_c_str, rand_c_datetime, rand_c_double)
 |  insert_or_replace into t (c_int, c_str, c_timestamp, c_decimal) values (next_c_int, rand_c_str, rand_c_timestamp, rand_c_decimal), (rand_c_int, rand_c_str, rand_c_timestamp, rand_c_decimal)
 |  insert into t values rows_to_ins on duplicate key update on_dup_assignments

common_delete:
    [weight=3] delete from t where predicates maybe_write_limit
 |  delete from t where c_int in ({ local k = G.c_int.seq:head(); print(k-math.random(3)) }, rand_c_int) maybe_write_limit
 |  delete from t where { print(util.choice({'c_int', 'c_str', 'c_decimal', 'c_double', 'c_datetime', 'c_timestamp'})) } is null maybe_write_limit
