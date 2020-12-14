init: create table t (a int auto_increment, primary key (a));
      alter table t set tiflash replica 1;
      select sleep(10);
      insert into t values (1), (2), (3);

txn: set @@session.tidb_isolation_read_engines=tiflash; select * from t; set @@session.tidb_isolation_read_engines='tikv,tiflash'; | insert into t values (0); txn
