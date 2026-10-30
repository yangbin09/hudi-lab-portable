#!/usr/bin/env bash
# =============================================================
# 清理本次冒烟测试创建的 Hudi 表（在 spark 容器内执行）
# 只删除带 run id 的测试表，不触碰用户自己的表。
# =============================================================
set -euo pipefail

RUN_ID="${1:?usage: cleanup-hudi.sh <run-id>}"
RUN_ID="$(printf '%s' "$RUN_ID" | tr -cd '0-9A-Za-z')"

SQL="/tmp/hudi-lab-portable-cleanup-${RUN_ID}.sql"

cat > "${SQL}" <<EOF
DROP TABLE IF EXISTS hudi_lab_portable_test.mor_${RUN_ID}_ro;
DROP TABLE IF EXISTS hudi_lab_portable_test.mor_${RUN_ID};
DROP TABLE IF EXISTS hudi_lab_portable_test.cow_${RUN_ID};
EOF

/opt/spark/bin/spark-sql -f "${SQL}" > "/tmp/hudi-lab-portable-cleanup-${RUN_ID}.out" 2>&1 || {
  echo "CLEANUP_WARN: spark-sql cleanup failed, see /tmp/hudi-lab-portable-cleanup-${RUN_ID}.out" >&2
  exit 1
}

echo "CLEANUP_PASS"
