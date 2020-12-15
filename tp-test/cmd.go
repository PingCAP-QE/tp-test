package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"sync/atomic"
	"time"

	"github.com/spf13/cobra"
	"github.com/zyguan/sqlz/resultset"
	"golang.org/x/sync/errgroup"
)

type global struct {
	storeDSN string
	store    Store
}

func rootCmd() *cobra.Command {
	var g global

	cmd := &cobra.Command{
		Use: "tp-test",
		PersistentPreRunE: func(cmd *cobra.Command, args []string) (err error) {
			g.store, err = NewStore(g.storeDSN)
			return
		},
	}
	cmd.PersistentFlags().StringVar(&g.storeDSN, "store", "", "mysql dsn of test store")
	cmd.AddCommand(initCmd(&g))
	cmd.AddCommand(clearCmd(&g))
	cmd.AddCommand(genTestCmd(&g))
	cmd.AddCommand(runTestCmd(&g))
	cmd.AddCommand(whyTestCmd(&g))
	return cmd
}

func initCmd(g *global) *cobra.Command {
	cmd := &cobra.Command{
		Use:           "init",
		Short:         "Initialize test store",
		SilenceErrors: true,
		SilenceUsage:  true,
		RunE: func(cmd *cobra.Command, args []string) error {
			return g.store.Init()
		},
	}
	return cmd
}

func clearCmd(g *global) *cobra.Command {
	cmd := &cobra.Command{
		Use:           "clear",
		Short:         "Clear test store",
		SilenceErrors: true,
		SilenceUsage:  true,
		RunE: func(cmd *cobra.Command, args []string) error {
			return g.store.Clear()
		},
	}
	return cmd
}

func genTestCmd(g *global) *cobra.Command {
	var (
		opts   genTestOptions
		tests  int
		dryrun bool
	)

	cmd := &cobra.Command{
		Use:           "gen <input file>",
		Short:         "Generate tests",
		SilenceErrors: true,
		SilenceUsage:  true,
		Args:          cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			yy, err := ioutil.ReadFile(args[0])
			if err != nil {
				return err
			}
			opts.Grammar = string(yy)
			for i := 0; i < tests; i++ {
				t, err := genTest(opts)
				if err != nil {
					return err
				}
				if dryrun {
					fmt.Printf("-- T%d.0\n", i)
					for _, stmt := range t.InitSQL {
						fmt.Println(stmt + ";")
					}
					for k, txn := range t.Steps {
						fmt.Printf("-- T%d.%d\n", i, k+1)
						for _, stmt := range txn {
							fmt.Println(stmt.Stmt+"; -- query:", naiveQueryDetect(stmt.Stmt))
						}
					}
				} else {
					if err := g.store.AddTest(t); err != nil {
						return err
					}
					log.Printf("test #%d added", i)
				}
			}
			return nil
		},
	}
	cmd.Flags().IntVar(&tests, "test", 1, "number of test to generate")
	cmd.Flags().BoolVar(&dryrun, "dry-run", false, "dry run")
	cmd.Flags().StringVar(&opts.InitRoot, "init-root", "init", "entry rule of initialization sql")
	cmd.Flags().StringVar(&opts.TxnRoot, "txn-root", "txn", "entry rule of transaction")
	cmd.Flags().IntVar(&opts.RecurLimit, "recur-limit", 15, "max recursion level for sql generation")
	cmd.Flags().IntVar(&opts.NumTxn, "txn", 5, "number of transactions per test")
	cmd.Flags().BoolVar(&opts.Debug, "debug", false, "enable debug option of generator")
	return cmd
}

func runTestCmd(g *global) *cobra.Command {
	var (
		opts runABTestOptions
		dsn1 string
		dsn2 string
		test uint32
	)

	cmd := &cobra.Command{
		Use:           "run",
		Short:         "Run generated tests",
		SilenceErrors: true,
		SilenceUsage:  true,
		RunE: func(cmd *cobra.Command, args []string) (err error) {
			opts.Store = g.store
			if opts.Threads <= 0 {
				opts.Threads = 1
			}
			if opts.DB1, err = sql.Open("mysql", dsn1); err != nil {
				return
			}
			if opts.DB2, err = sql.Open("mysql", dsn2); err != nil {
				return
			}
			if test > 0 {
				var cnt uint32
				opts.Continue = func() bool {
					return atomic.AddUint32(&cnt, 1) <= test
				}
			}
			var g errgroup.Group
			failed := make(chan struct{})
			for i := 0; i < opts.Threads; i++ {
				g.Go(func() error { return runABTest(context.Background(), failed, opts) })
			}
			return g.Wait()
		},
	}
	cmd.Flags().Uint32Var(&test, "test", 0, "number of tests to run")
	cmd.Flags().StringVar(&dsn1, "dsn1", "", "dsn for 1st database")
	cmd.Flags().StringVar(&dsn2, "dsn2", "", "dsn for 2nd database")
	cmd.Flags().StringVar(&opts.Tag1, "tag1", "A", "tag of 1st database")
	cmd.Flags().StringVar(&opts.Tag2, "tag2", "B", "tag of 2nd database")
	cmd.Flags().StringSliceVar(&opts.TiFlashTables, "tiflash-tables", []string{}, "tables needed to wait for replication available, eg. 1:t1,1:t2")
	cmd.Flags().IntVar(&opts.Threads, "thread", 1, "number of worker threads")
	cmd.Flags().IntVar(&opts.QueryTimeout, "query-timeout", 30, "timeout in seconds for a singe query")
	return cmd
}

func whyTestCmd(g *global) *cobra.Command {
	cmd := &cobra.Command{
		Use:           "why <test id>",
		Short:         "Explain a test",
		SilenceErrors: true,
		SilenceUsage:  true,
		Args:          cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			id := args[0]
			db, err := sql.Open("mysql", g.storeDSN)
			if err != nil {
				return err
			}
			var (
				t       Test
				initRaw []byte
			)
			row := db.QueryRow("select status, started_at, finished_at, message, init_sql from test where id = ?", id)
			if err := row.Scan(&t.Status, &t.StartedAt, &t.FinishedAt, &t.Message, &initRaw); err != nil {
				return err
			}
			if err := json.Unmarshal(initRaw, &t.InitSQL); err != nil {
				return err
			}
			t1 := time.Unix(t.StartedAt, 0)
			t2 := t1
			if t.FinishedAt > t.StartedAt {
				t2 = time.Unix(t.FinishedAt, 0)
			}
			fmt.Printf("# [%s] %s (%s,%s)\n", t.Status, id, t1.Format(time.RFC3339), t2.Sub(t1))
			if len(t.Message) > 0 {
				fmt.Println("\n> " + t.Message)
			}
			if t.Status != TestFailed {
				return nil
			}

			dumpRes := func(tag string, raw []byte, err string) {
				fmt.Println("\n**" + tag + "**")
				if len(err) > 0 {
					fmt.Println("Error: " + err)
					return
				}
				var rs resultset.ResultSet
				if e := rs.Decode(raw); e != nil {
					fmt.Println("oops: " + e.Error())
					return
				}
				rs.PrettyPrint(os.Stdout)
			}

			dumpStmts := func(seq int) {
				var (
					stmt    Stmt
					lastTxn = -1
				)
				fmt.Println("-- init")
				for _, stmt := range t.InitSQL {
					fmt.Println(stmt + ";")
				}

				rows, err := db.Query("select stmt, txn from stmt where test_id = ? and seq <= ? order by seq", id, seq)
				if err != nil {
					fmt.Println("oops: " + err.Error())
					return
				}
				defer rows.Close()
				for rows.Next() {
					if err := rows.Scan(&stmt.Stmt, &stmt.Txn); err != nil {
						fmt.Println("oops: " + err.Error())
						return
					}
					if lastTxn != stmt.Txn {
						if lastTxn != -1 {
							fmt.Println("commit;")
						}
						fmt.Printf("-- txn:%d\n", stmt.Txn)
						fmt.Println("begin;")
					}
					fmt.Println(stmt.Stmt + ";")
					lastTxn = stmt.Txn
				}
				if err := rows.Err(); err != nil {
					fmt.Println("oops: " + err.Error())
				}
			}

			var (
				seq  int
				stmt string
			)
			if err := db.QueryRow("select seq from stmt_result where test_id = ? order by seq desc", id).Scan(&seq); err != nil {
				return err
			}
			if err := db.QueryRow("select stmt from stmt where test_id = ? and seq = ?", id, seq).Scan(&stmt); err != nil {
				return err
			}
			fmt.Println("\n## last query")
			fmt.Printf("\n%d: %s\n", seq, stmt)

			fmt.Println("\n```")
			rows, err := db.Query("select tag, result, errmsg from stmt_result where test_id = ? and seq = ? order by tag", id, seq)
			if err != nil {
				fmt.Println("oops: " + err.Error())
			} else {
				defer rows.Close()
				for rows.Next() {
					var (
						tag string
						err string
						raw []byte
					)
					if rows.Scan(&tag, &raw, &err) == nil {
						dumpRes(tag, raw, err)
					}
				}
			}
			fmt.Println("\n```")

			fmt.Println("\n## history")

			fmt.Println("\n```sql")
			dumpStmts(seq)
			fmt.Println("```")

			return nil
		},
	}
	return cmd
}
