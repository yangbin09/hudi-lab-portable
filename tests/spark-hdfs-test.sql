-- Spark + HDFS 冒烟测试：写入 Parquet 到 HDFS 再读回校验
-- 占位符 __RUN_ID__ 由 tests/test-spark.sh 替换

DROP TABLE IF EXISTS spark_hdfs_test___RUN_ID__;

CREATE TABLE spark_hdfs_test___RUN_ID__ (
  id   BIGINT,
  name STRING
) USING parquet
LOCATION 'hdfs://namenode:9000/tmp/hudi-lab-portable-test/__RUN_ID__/spark-parquet';

INSERT INTO spark_hdfs_test___RUN_ID__ VALUES (1, 'alice'), (2, 'bob'), (3, 'carol');

SELECT CASE WHEN COUNT(*) = 3 AND SUM(id) = 6 THEN 'SPARK_TEST_PASS'
            ELSE CONCAT('SPARK_TEST_FAIL: count=', CAST(COUNT(*) AS STRING),
                        ' sum=', CAST(SUM(id) AS STRING)) END AS result
FROM spark_hdfs_test___RUN_ID__;

SELECT id, name FROM spark_hdfs_test___RUN_ID__ ORDER BY id;

DROP TABLE IF EXISTS spark_hdfs_test___RUN_ID__;
