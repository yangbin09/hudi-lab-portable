-- =============================================================
-- Hudi Lab Portable —— COW 冒烟测试
-- 占位符 __RUN_ID__ 由 tests/test-hudi.sh 在运行期替换。
--
-- 兼容处理（沿用已验证环境）：
--   显式关闭 metadata table 与 Hive Sync，避免 Spark 自带
--   hadoop-client 3.3.2 与 Hudi bundle 内置 HBase 的
--   NoSuchMethodError: HdfsDataInputStream.getReadStatistics
-- =============================================================

CREATE DATABASE IF NOT EXISTS hudi_lab_portable_test;
USE hudi_lab_portable_test;

DROP TABLE IF EXISTS cow___RUN_ID__;

CREATE TABLE cow___RUN_ID__ (
  id        BIGINT,
  customer  STRING,
  amount    DOUBLE,
  ts        BIGINT,
  dt        STRING
) USING hudi
PARTITIONED BY (dt)
TBLPROPERTIES (
  type                                 = 'cow',
  primaryKey                           = 'id',
  preCombineField                      = 'ts',
  `hoodie.table.name`                  = 'cow___RUN_ID__',
  `hoodie.metadata.enable`             = 'false',
  `hoodie.datasource.hive_sync.enable` = 'false'
)
LOCATION 'hdfs://namenode:9000/tmp/hudi-lab-portable-test/__RUN_ID__/cow';

-- ---------- INSERT ----------
INSERT INTO cow___RUN_ID__ VALUES
  (1001, 'alice', 110.5, 1000, '2024-01-01'),
  (1002, 'bob',   220.0, 1001, '2024-01-01'),
  (1003, 'carol', 330.5, 1002, '2024-01-01'),
  (1004, 'dave',  440.0, 1003, '2024-01-02'),
  (1005, 'eve',   550.5, 1004, '2024-01-02'),
  (1006, 'frank', 660.0, 1005, '2024-01-02');

SELECT CASE WHEN COUNT(*) = 6 THEN 'COW_INSERT_PASS'
            ELSE CONCAT('COW_INSERT_FAIL: rows=', CAST(COUNT(*) AS STRING)) END AS result
FROM cow___RUN_ID__;

-- ---------- UPDATE ----------
UPDATE cow___RUN_ID__
SET amount = 999.9, customer = 'bob-updated', ts = 2000
WHERE id = 1002;

SELECT CASE WHEN COUNT(*) = 1 THEN 'COW_UPDATE_PASS'
            ELSE CONCAT('COW_UPDATE_FAIL: rows=', CAST(COUNT(*) AS STRING)) END AS result
FROM cow___RUN_ID__
WHERE id = 1002 AND customer = 'bob-updated' AND amount = 999.9;

-- ---------- DELETE ----------
DELETE FROM cow___RUN_ID__ WHERE id = 1006;

SELECT CASE WHEN COUNT(*) = 5 THEN 'COW_DELETE_PASS'
            ELSE CONCAT('COW_DELETE_FAIL: rows=', CAST(COUNT(*) AS STRING)) END AS result
FROM cow___RUN_ID__;

-- ---------- PARTITIONS ----------
SHOW PARTITIONS cow___RUN_ID__;

-- ---------- TIMELINE（元数据列）----------
-- 说明：已删除的记录不再出现在结果里，因此当前快照只保留
-- “插入/更新”这两类 commit 时间；完整 commit 数量由
-- tests/verify-hudi-layout.sh 直接检查 .hoodie 目录。
SELECT CASE WHEN COUNT(DISTINCT _hoodie_commit_time) >= 2 THEN 'COW_TIMELINE_PASS'
            ELSE CONCAT('COW_TIMELINE_FAIL: commits=', CAST(COUNT(DISTINCT _hoodie_commit_time) AS STRING)) END AS result
FROM cow___RUN_ID__;

SELECT DISTINCT _hoodie_commit_time AS commit_time FROM cow___RUN_ID__ ORDER BY commit_time;

-- ---------- BASE FILE ----------
SELECT CASE WHEN SUM(CASE WHEN _hoodie_file_name LIKE '%.parquet' THEN 1 ELSE 0 END) = COUNT(*)
            THEN 'COW_BASEFILE_PASS'
            ELSE 'COW_BASEFILE_FAIL' END AS result
FROM cow___RUN_ID__;
