#!/usr/bin/env bash
# =============================================================
# Hudi 物理布局校验（在 namenode 容器内执行）
#   - COW: .hoodie 下 commit 文件、parquet base file
#   - MOR: deltacommit 文件、parquet base file、.log.* 日志文件
# 不做硬编码行数断言，只验证真实文件形态。
# =============================================================
set -euo pipefail

RUN_ID="${1:?usage: verify-hudi-layout.sh <run-id>}"
RUN_ID="$(printf '%s' "$RUN_ID" | tr -cd '0-9A-Za-z')"

ROOT="/tmp/hudi-lab-portable-test/${RUN_ID}"
COW="${ROOT}/cow"
MOR="${ROOT}/mor"

fail() {
  echo "HUDI_LAYOUT_FAIL: $*" >&2
  exit 1
}

count_matches() {
  # $1=dir  $2=extended regex
  hdfs dfs -ls "$1" 2>/dev/null | grep -cE "$2" || true
}

find_count() {
  # $1=dir  $2=glob
  hdfs dfs -find "$1" -name "$2" 2>/dev/null | wc -l | tr -d ' '
}

hdfs dfs -test -d "${COW}/.hoodie" || fail "COW .hoodie missing: ${COW}/.hoodie"
hdfs dfs -test -d "${MOR}/.hoodie" || fail "MOR .hoodie missing: ${MOR}/.hoodie"

COW_COMMITS="$(count_matches "${COW}/.hoodie" '\.commit$')"
COW_PARQUET="$(find_count "${COW}" '*.parquet')"

MOR_DELTAS="$(count_matches "${MOR}/.hoodie" '\.deltacommit$')"
MOR_COMMITS="$(count_matches "${MOR}/.hoodie" '\.commit$')"
MOR_PARQUET="$(find_count "${MOR}" '*.parquet')"
MOR_LOGS="$(find_count "${MOR}" '*.log.*')"

echo "[hudi-layout] COW commits=${COW_COMMITS} parquet=${COW_PARQUET}"
echo "[hudi-layout] MOR deltacommits=${MOR_DELTAS} commits=${MOR_COMMITS} parquet=${MOR_PARQUET} logfiles=${MOR_LOGS}"

[ "${COW_COMMITS}" -ge 3 ] || fail "COW commit count ${COW_COMMITS} < 3"
[ "${COW_PARQUET}" -gt 0 ] || fail "COW parquet base files = 0"
[ "${MOR_DELTAS}" -ge 1 ] || fail "MOR deltacommit count = 0"
[ "${MOR_PARQUET}" -gt 0 ] || fail "MOR parquet base files = 0"
[ "${MOR_LOGS}" -gt 0 ] || fail "MOR log files = 0 (inline compaction may be on)"

if hdfs dfs -test -d "${COW}/.hoodie/metadata"; then
  echo "[hudi-layout][WARN] metadata table directory exists (expected disabled)"
else
  echo "[hudi-layout] metadata table disabled (no .hoodie/metadata)"
fi

echo "HUDI_LAYOUT_PASS"
