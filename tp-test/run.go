package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/go-sql-driver/mysql"
	"github.com/zyguan/sqlz"
	"github.com/zyguan/sqlz/resultset"

	. "github.com/zyguan/just"
)

type runABTestOptions struct {
	Threads      int
	QueryTimeout int
	Continue     func() bool

	Tag1 string
	Tag2 string
	DB1  *sql.DB
	DB2  *sql.DB

	TiFlashTables []string

	Store Store
}

func (opts *runABTestOptions) TiFlashTablesForDB(i int) []string {
	tbls := make([]string, 0, len(opts.TiFlashTables))
	prefix := strconv.Itoa(i) + ":"
	for _, t := range opts.TiFlashTables {
		if strings.HasPrefix(t, prefix) {
			tbls = append(tbls, strings.TrimPrefix(t, prefix))
		}
	}
	return tbls
}

func runABTest(ctx context.Context, failed chan struct{}, opts runABTestOptions) error {
	store := opts.Store

	if opts.Continue == nil {
		opts.Continue = func() bool { return true }
	}
	for opts.Continue() {
		select {
		case <-failed:
			return nil
		case <-ctx.Done():
			return nil
		default:
		}

		t, err := store.NextPendingTest()
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				log.Printf("no more test")
				return nil
			}
			return err
		}

		// using different db names allows us run test on same db instance
		dbName1 := "db1__" + strings.ReplaceAll(t.ID, "-", "_")
		dbName2 := "db2__" + strings.ReplaceAll(t.ID, "-", "_")

		conn1, err1 := initTest(ctx, opts.DB1, dbName1, t, opts.TiFlashTablesForDB(1))
		if err1 != nil {
			store.SetTest(t.ID, TestFailed, "init db1: "+err1.Error())
			log.Printf("failed to init %s/%s: %v", opts.Tag1, dbName1, err1)
			continue
		}
		conn2, err2 := initTest(ctx, opts.DB2, dbName2, t, opts.TiFlashTablesForDB(2))
		if err2 != nil {
			conn1.Close()
			store.SetTest(t.ID, TestFailed, "init db2: "+err2.Error())
			log.Printf("failed to init %s/%s: %v", opts.Tag2, dbName2, err2)
			continue
		}
		closeConns := func() {
			conn1.Close()
			conn2.Close()
		}

		log.Printf("run test %s", t.ID)
		for i := range t.Groups {
			fail := func(err error) error {
				defer func() { recover() }()
				conn1.ExecContext(ctx, "rollback")
				conn2.ExecContext(ctx, "rollback")
				closeConns()
				store.SetTest(t.ID, TestFailed, err.Error())
				log.Printf("test(%s) failed at txn #%d: %v", t.ID, i, err)
				close(failed)
				return err
			}

			if err := doStmts(ctx, opts, t, i, conn1, conn2); err != nil {
				return fail(err)
			}

			hs1, err1 := checkTables(ctx, opts.DB1, dbName1)
			if err1 != nil {
				return fail(fmt.Errorf("check table of %s after txn #%d: %v", opts.Tag1, i, err1))
			}
			hs2, err2 := checkTables(ctx, opts.DB2, dbName2)
			if err2 != nil {
				return fail(fmt.Errorf("check table of %s after txn #%d: %v", opts.Tag2, i, err2))
			}
			for t := range hs2 {
				if hs1[t] != hs2[t] {
					return fail(fmt.Errorf("data mismatch @%s", t))
				}
			}
		}

		store.SetTest(t.ID, TestPassed, "")

		conn1.ExecContext(ctx, "drop database if exists "+dbName1)
		conn2.ExecContext(ctx, "drop database if exists "+dbName2)
		closeConns()
	}
	return nil
}

func initTest(ctx context.Context, db *sql.DB, name string, t *Test, tiflashTbls []string) (conn *sql.Conn, err error) {
	defer Return(&err)
	conn = Try(sqlz.Connect(ctx, db)).(*sql.Conn)
	Try(conn.ExecContext(ctx, "create database "+name))
	Try(conn.ExecContext(ctx, "use "+name))
	for _, stmt := range t.InitSQL {
		// it's ok for some of stmts in init_sql failed
		if _, err := conn.ExecContext(ctx, stmt); err != nil {
			log.Printf("init stmt failed: %v @ %s", err, stmt)
		}
	}
	for _, tbl := range tiflashTbls {
		avail := 0
		for i := 0; i < 30; i++ {
			e := conn.QueryRowContext(ctx, "select available from information_schema.tiflash_replica where table_schema = ? and table_name = ?", name, tbl).Scan(&avail)
			if e != nil {
				log.Printf("failed to select tiflash_replica: [%s] %v", tbl, e)
				break
			}
			if avail > 0 {
				break
			}
			log.Printf("waiting replication: [%s]", tbl)
			time.Sleep(time.Second)
		}
	}
	return
}

func checkTables(ctx context.Context, db *sql.DB, name string) (map[string]string, error) {
	rows, err := db.QueryContext(ctx, "select table_name from information_schema.tables where table_schema = ?", name)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	hs := make(map[string]string)
	for rows.Next() {
		var t string
		if err = rows.Scan(&t); err != nil {
			return nil, err
		}
		if hs[t], err = checkTable(ctx, db, fmt.Sprintf("`%s`.`%s`", name, t)); err != nil {
			return nil, err
		}
	}
	if err = rows.Err(); err != nil {
		return nil, err
	}
	return hs, nil
}

func checkTable(ctx context.Context, db *sql.DB, name string) (string, error) {
	_, err := db.ExecContext(ctx, "admin check table "+name)
	if err != nil {
		if e, ok := err.(*mysql.MySQLError); !ok || e.Number != 1064 {
			return "", err
		}
	}
	rows, err := db.QueryContext(ctx, "select * from "+name)
	if err != nil {
		return "", err
	}
	defer rows.Close()
	rs, err := resultset.ReadFromRows(rows)
	if err != nil {
		return "", err
	}
	return rs.DataDigest(resultset.DigestOptions{
		Sort: true,
		Filter: func(i int, j int, raw []byte, _ resultset.ColumnDef) bool {
			return rs.ColumnDef(j).Type != "JSON"
		}},
	), nil
}

func doStmts(ctx context.Context, opts runABTestOptions, t *Test, i int, s1 *sql.Conn, s2 *sql.Conn) error {
	txn := t.Groups[i]

	record := func(seq int, tag string, rs *resultset.ResultSet, err error) {
		if rs != nil {
			raw, _ := rs.Encode()
			opts.Store.PutStmtResult(t.ID, seq, tag, Result{
				Raw:          raw,
				Err:          err,
				RowsAffected: rs.ExecResult().RowsAffected,
				LastInsertId: rs.ExecResult().LastInsertId,
			})
		} else {
			opts.Store.PutStmtResult(t.ID, seq, tag, Result{Err: err})
		}
	}

	for _, stmt := range txn {
		if stmt.IsQuery {
			k := numOfPlans(ctx, s1, stmt.Stmt, 99)
			if k > 1 {
				if err := checkEachPlan(ctx, s1, stmt.Stmt, k); err != nil {
					return err
				}
				stmt.Stmt = strings.Replace(stmt.Stmt, "nth_plan(?)", "nth_plan(1)", 1)
			}
		}
		ctx1, _ := context.WithTimeout(ctx, time.Duration(opts.QueryTimeout)*time.Second)
		rs1, err1 := doStmt(ctx1, s1, stmt)
		record(stmt.Seq, opts.Tag1, rs1, err1)
		ctx2, _ := context.WithTimeout(ctx, time.Duration(opts.QueryTimeout)*time.Second)
		rs2, err2 := doStmt(ctx2, s2, stmt)
		record(stmt.Seq, opts.Tag2, rs2, err2)
		if !validateErrs(err1, err2) {
			return fmt.Errorf("errors mismatch: %v <> %v @(%s,%d) %q", err1, err2, t.ID, stmt.Seq, stmt.Stmt)
		}
		if rs1 == nil || rs2 == nil {
			log.Printf("skip query error: [%v] [%v] @(%s,%d)", err1, err2, t.ID, stmt.Seq)
			continue
		}
		digestOpts := resultset.DigestOptions{
			Sort: true,
			Filter: func(i int, j int, raw []byte, _ resultset.ColumnDef) bool {
				if strings.Contains(stmt.Stmt, "union") {
					typ := rs1.ColumnDef(j).Type
					return typ != "FLOAT" && typ != "DOUBLE"
				}
				return true
			},
		}
		h1, h2 := rs1.DataDigest(digestOpts), rs2.DataDigest(digestOpts)
		if h1 != h2 {
			return fmt.Errorf("result digests mismatch @(%s,%d) %q", t.ID, stmt.Seq, stmt.Stmt)
		}
		//if rs1.IsExecResult() && rs1.ExecResult().RowsAffected != rs2.ExecResult().RowsAffected {
		//	return fmt.Errorf("rows affected mismatch: %d != %d @(%s,%d) %q",
		//		rs1.ExecResult().RowsAffected, rs2.ExecResult().RowsAffected, t.ID, stmt.Seq, stmt.Stmt)
		//}
	}
	return nil
}

func doStmt(ctx context.Context, s *sql.Conn, stmt Stmt) (*resultset.ResultSet, error) {
	if stmt.IsQuery {
		rows, err := s.QueryContext(ctx, "/* tp-test:q:"+stmt.TestID+":"+strconv.Itoa(stmt.Seq)+" */ "+stmt.Stmt)
		if err != nil {
			return nil, err
		}
		defer rows.Close()
		return resultset.ReadFromRows(rows)
	} else {
		res, err := s.ExecContext(ctx, "/* tp-test:e:"+stmt.TestID+":"+strconv.Itoa(stmt.Seq)+" */ "+stmt.Stmt)
		if err != nil {
			return nil, err
		}
		return resultset.NewFromResult(res), nil
	}
}

func validateErrs(err1 error, err2 error) bool {
	return (err1 == nil && err2 == nil) || (err1 != nil && err2 != nil)
}

func numOfPlans(ctx context.Context, c *sql.Conn, stmt string, max int) int {
	if !strings.Contains(stmt, "nth_plan(?)") {
		return 1
	}
	nth := sort.Search(max, func(i int) bool {
		q := strings.Replace(stmt, "nth_plan(?)", "nth_plan("+strconv.Itoa(i+1)+")", 1)
		c.ExecContext(ctx, q)
		warnings := 0
		c.QueryRowContext(ctx, "select @@warning_count").Scan(&warnings)
		return warnings > 0
	})
	return nth
}

func checkEachPlan(ctx context.Context, c *sql.Conn, stmt string, n int) error {
	lastStmt, lastDigest := "", ""
	for i := 0; i < n; i++ {
		thisStmt := strings.Replace(stmt, "nth_plan(?)", "nth_plan("+strconv.Itoa(i+1)+")", 1)
		rows, err := c.QueryContext(ctx, thisStmt)
		if err != nil {
			log.Printf("%q -> %v", thisStmt, err)
			//if strings.Contains(err.Error(), "PlanCounterTp planCounter is not handled") {
			//	continue
			//}
			return err
		}
		rs, err := resultset.ReadFromRows(rows)
		if err != nil {
			rows.Close()
			return err
		}
		thisDigest := rs.DataDigest(resultset.DigestOptions{Sort: true})
		log.Printf("%q -> %s", thisStmt, thisDigest)
		if len(lastStmt) > 0 && lastDigest != thisDigest {
			return fmt.Errorf("(%s:%q) != (%s:%q)", lastDigest, lastStmt, thisDigest, thisStmt)
		}
		lastStmt, lastDigest = thisStmt, thisDigest
	}
	return nil
}
