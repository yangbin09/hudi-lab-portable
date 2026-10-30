#!/usr/bin/env bash
# =============================================================
# HDFS 冒烟测试（在 namenode 容器内执行）
#   - mkdir / put / cat / ls
#   - dfsadmin -report：Live DataNodes 与 Safe Mode
#   - fsck：Block 状态 HEALTHY
# 只操作 /tmp/hudi-lab-portable-test/<run-id>，不触碰用户数据。
# =============================================================
set -euo pipefail

RUN_ID="${1:-$(date +%Y%m%d%H%M%S)}"
RUN_ID="$(printf '%s' "$RUN_ID" | tr -cd '0-9A-Za-z')"
BASE="/tmp/hudi-lab-portable-test/${RUN_ID}"
PAYLOAD="hudi-lab-portable hdfs smoke test ${RUN_ID}"

fail() {
  echo "HDFS_TEST_FAIL: $*" >&2
  exit 1
}

echo "[hdfs-test] run id : ${RUN_ID}"
echo "[hdfs-test] path   : ${BASE}"

hdfs dfs -mkdir -p "${BASE}" || fail "mkdir ${BASE}"
hdfs dfs -ls / >/dev/null || fail "ls /"

printf '%s\n' "${PAYLOAD}" > /tmp/hudi-lab-payload.txt
hdfs dfs -put -f /tmp/hudi-lab-payload.txt "${BASE}/payload.txt" || fail "put"
hdfs dfs -ls "${BASE}" | grep -q 'payload.txt' || fail "uploaded file not listed"

GOT="$(hdfs dfs -cat "${BASE}/payload.txt")"
[ "${GOT}" = "${PAYLOAD}" ] || fail "content mismatch: '${GOT}'"

hdfs dfsadmin -report > /tmp/hudi-lab-hdfs-report.txt 2>/dev/null || fail "dfsadmin -report"
grep -q 'Live datanodes (1)' /tmp/hudi-lab-hdfs-report.txt || fail "Live DataNodes != 1"
hdfs dfsadmin -safemode get | grep -q 'Safe mode is OFF' || fail "Safe Mode is not OFF"

hdfs fsck "${BASE}" -files -blocks > /tmp/hudi-lab-hdfs-fsck.txt 2>&1 || true
grep -q 'Status: HEALTHY' /tmp/hudi-lab-hdfs-fsck.txt || fail "fsck status is not HEALTHY"

echo "[hdfs-test] $(grep -m1 'Live datanodes' /tmp/hudi-lab-hdfs-report.txt | tr -d '\r')"
echo "[hdfs-test] $(grep -m1 'Status:' /tmp/hudi-lab-hdfs-fsck.txt | tr -d '\r')"
echo "HDFS_TEST_PASS"
