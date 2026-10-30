#!/usr/bin/env bash
# =============================================================
# Spark + HDFS 冒烟测试（在 spark 容器内执行）
#   Spark SQL 读写 HDFS Parquet，并校验写入与读取结果一致。
# =============================================================
set -euo pipefail

RUN_ID="${1:-$(date +%Y%m%d%H%M%S)}"
RUN_ID="$(printf '%s' "$RUN_ID" | tr -cd '0-9A-Za-z')"
WORK="/tmp/hudi-lab-portable-${RUN_ID}"
mkdir -p "${WORK}"

SQL="${WORK}/spark-hdfs.sql"
OUT="${WORK}/spark-hdfs.out"
sed "s/__RUN_ID__/${RUN_ID}/g" /opt/hudi-lab/tests/spark-hdfs-test.sql > "${SQL}"

echo "[spark-test] run id : ${RUN_ID}"
echo "[spark-test] spark  : $(/opt/spark/bin/spark-submit --version 2>&1 | grep -m1 -oE 'version [0-9.]+' | head -1)"

if ! /opt/spark/bin/spark-sql -f "${SQL}" > "${OUT}" 2>&1; then
  echo "SPARK_TEST_FAIL: spark-sql exited with error" >&2
  tail -n 60 "${OUT}" >&2
  exit 1
fi

if ! grep -q 'SPARK_TEST_PASS' "${OUT}"; then
  echo "SPARK_TEST_FAIL: marker not found" >&2
  grep -E 'SPARK_TEST_(PASS|FAIL)' "${OUT}" >&2 || tail -n 60 "${OUT}" >&2
  exit 1
fi

grep -E '^(1|2|3)[[:space:]]' "${OUT}" | tr -d '\r' || true
echo "SPARK_TEST_PASS"
