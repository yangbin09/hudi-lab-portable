-- =============================================================
-- Hudi Lab Portable —— MOR 冒烟测试
-- 占位符 __RUN_ID__ 由 tests/test-hudi.sh 在运行期替换。
--
-- 关闭 inline compaction，便于观察真实的 Base File + Log File。
-- 同样关闭 metadata table / Hive Sync（兼容性原因见 cow-test.sql）。
-- =============================================================

CREATE DATABASE IF NOT EXISTS hudi_lab_portable_test;
USE hudi_lab_portable_test;

DROP TABLE IF EXISTS mor___RUN_ID___ro;
DROP TABLE IF EXISTS mor___RUN_ID__;

CREATE TABLE mor___RUN_ID__ (
  id        BIGINT,
  customer  STRING,
  status    STRING,
  amount    DOUBLE,
  ts        BIGINT,
  dt        STRING
) USING hudi
PARTITIONED BY (dt)
TBLPROPERTIES (
  type                                       = 'mor',
  primaryKey                                 = 'id',
  preCombineField                            = 'ts',
  `hoodie.table.name`                        = 'mor___RUN_ID__',
  `hoodie.compact.inline`                    = 'false',
  `hoodie.compact.inline.max.delta.commits`  = '10',
  `hoodie.metadata.enable`                   = 'false',
  `hoodie.datasource.hive_sync.enable`       = 'false'
)
LOCATION 'hdfs://namenode:9000/tmp/hudi-lab-portable-test/__RUN_ID__/mor';

-- ---------- INSERT ----------
INSERT INTO mor___RUN_ID__ VALUES
  (2001, 'c1', 'NEW',       10.0, 1000, '2024-01-01'),
  (2002, 'c2', 'NEW',       20.0, 1001, '2024-01-01'),
  (2003, 'c3', 'PAID',      30.0, 1002, '2024-01-01'),
  (2004, 'c4', 'PAID',      40.0, 1003, '2024-01-02'),
  (2005, 'c5', 'PAID',      50.0, 1004, '2024-01-02'),
  (2006, 'c6', 'CANCELLED', 60.0, 1005, '2024-01-02');

SELECT CASE WHEN COUNT(*) = 6 THEN 'MOR_INSERT_PASS'
            ELSE CONCAT('MOR_INSERT_FAIL: rows=', CAST(COUNT(*) AS STRING)) END AS result
FROM mor___RUN_ID__;

-- ---------- UPDATE（MOR 写 log 文件）----------
UPDATE mor___RUN_ID__ SET status = 'SHIPPED', ts = 2000 WHERE id = 2001;
UPDATE mor___RUN_ID__ SET status = 'SHIPPED', ts = 2001 WHERE id = 2002;
UPDATE mor___RUN_ID__ SET amount = 888.8,    ts = 3000 WHERE id = 2003;

-- ---------- DELETE ----------
DELETE FROM mor___RUN_ID__ WHERE id = 2006;

-- ---------- 快照查询 ----------
SELECT CASE WHEN COUNT(*) = 5 THEN 'MOR_SNAPSHOT_PASS'
            ELSE CONCAT('MOR_SNAPSHOT_FAIL: rows=', CAST(COUNT(*) AS STRING)) END AS result
FROM mor___RUN_ID__;

SELECT CASE WHEN COUNT(*) = 2 AND SUM(CASE WHEN status = 'SHIPPED' THEN 1 ELSE 0 END) = 2
            THEN 'MOR_UPDATE_PASS'
            ELSE CONCAT('MOR_UPDATE_FAIL: rows=', CAST(COUNT(*) AS STRING)) END AS result
FROM mor___RUN_ID__
WHERE id IN (2001, 2002);

-- ---------- 读优化查询（Base File）----------
-- 未做 compaction，_ro 读到的行数取决于真实 Base File 内容，
-- 这里只验证可读且非空，不硬编码预期行数。
SELECT CASE WHEN COUNT(*) > 0 THEN 'MOR_RO_PASS'
            ELSE 'MOR_RO_FAIL: empty' END AS result
FROM mor___RUN_ID___ro;

SELECT COUNT(*) AS ro_row_count FROM mor___RUN_ID___ro;

-- ---------- PARTITIONS ----------
SHOW PARTITIONS mor___RUN_ID__;

-- ---------- TIMELINE（元数据列）----------
SELECT CASE WHEN COUNT(DISTINCT _hoodie_commit_time) >= 2 THEN 'MOR_TIMELINE_PASS'
            ELSE CONCAT('MOR_TIMELINE_FAIL: commits=', CAST(COUNT(DISTINCT _hoodie_commit_time) AS STRING)) END AS result
FROM mor___RUN_ID__;

SELECT DISTINCT _hoodie_commit_time AS commit_time FROM mor___RUN_ID__ ORDER BY commit_time;
