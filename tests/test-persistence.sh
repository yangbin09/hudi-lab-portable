#!/usr/bin/env bash
# =============================================================
# 持久化校验（在 spark 容器内执行）
# 容器重建后，Derby 元数据与 Hudi/HDFS 数据仍应存在。
# 需要在 COW 测试之后、清理之前调用。
# =============================================================
set -euo pipefail

RUN_ID="${1:?usage: test-persistence.sh <run-id>}"
RUN_ID="$(printf '%s' "$RUN_ID" | tr -cd '0-9A-Za-z')"

OUT="/tmp/hudi-lab-portable-persistence-${RUN_ID}.out"

/opt/spark/bin/spark-sql -e "
SELECT CASE WHEN COUNT(*) = 5 THEN 'PERSISTENCE_PASS'
            ELSE CONCAT('PERSISTENCE_FAIL: rows=', CAST(COUNT(*) AS STRING)) END AS result
FROM hudi_lab_portable_test.cow_${RUN_ID};
" > "${OUT}" 2>&1 || {
  echo "PERSISTENCE_FAIL: query failed" >&2
  tail -n 60 "${OUT}" >&2
  exit 1
}

if ! grep -q 'PERSISTENCE_PASS' "${OUT}"; then
  echo "PERSISTENCE_FAIL: marker not found" >&2
  grep -E 'PERSISTENCE_(PASS|FAIL)' "${OUT}" >&2 || tail -n 60 "${OUT}" >&2
  exit 1
fi

echo "PERSISTENCE_PASS"
