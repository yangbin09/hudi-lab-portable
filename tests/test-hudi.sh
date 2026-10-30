#!/usr/bin/env bash
# =============================================================
# Hudi CRUD 冒烟测试（在 spark 容器内执行）
#   COW: create / insert / update / delete / select / partitions / timeline
#   MOR: create / insert / update / delete / snapshot / read-optimized
# 表名与 HDFS 路径都带 run id，只清理本次创建的测试资源。
# COW 与 MOR 相互独立：一个失败不会跳过另一个。
# =============================================================
set -uo pipefail

RUN_ID="${1:-$(date +%Y%m%d%H%M%S)}"
RUN_ID="$(printf '%s' "$RUN_ID" | tr -cd '0-9A-Za-z')"
WORK="/tmp/hudi-lab-portable-hudi-${RUN_ID}"
mkdir -p "${WORK}"

COW_OK=0
MOR_OK=0

check_markers() {
  local out="$1"
  local prefix="$2"
  local marker
  shift 2
  for marker in "$@"; do
    if grep -q "${marker}" "${out}"; then
      echo "[hudi-test] ${marker}"
    else
      echo "HUDI_${prefix}_FAIL: missing ${marker}" >&2
      grep -E "${prefix}_[A-Z]+_(PASS|FAIL)" "${out}" >&2 || tail -n 80 "${out}" >&2
      return 1
    fi
  done
  return 0
}

echo "[hudi-test] run id : ${RUN_ID}"

# ------------------------- COW -------------------------
echo "[hudi-test] running COW ..."
sed "s/__RUN_ID__/${RUN_ID}/g" /workspace/sql/cow-test.sql > "${WORK}/cow.sql"

if /opt/spark/bin/spark-sql -f "${WORK}/cow.sql" > "${WORK}/cow.out" 2>&1; then
  if check_markers "${WORK}/cow.out" COW \
      COW_INSERT_PASS COW_UPDATE_PASS COW_DELETE_PASS COW_TIMELINE_PASS COW_BASEFILE_PASS \
     && grep -q 'dt=2024-01-01' "${WORK}/cow.out"; then
    COW_OK=1
    echo "[hudi-test] COW CRUD + timeline OK"
  else
    echo "HUDI_COW_FAIL: marker or partition check failed" >&2
  fi
else
  echo "HUDI_COW_FAIL: spark-sql exited with error" >&2
  tail -n 80 "${WORK}/cow.out" >&2
fi

# ------------------------- MOR -------------------------
echo "[hudi-test] running MOR ..."
sed "s/__RUN_ID__/${RUN_ID}/g" /workspace/sql/mor-test.sql > "${WORK}/mor.sql"

if /opt/spark/bin/spark-sql -f "${WORK}/mor.sql" > "${WORK}/mor.out" 2>&1; then
  if check_markers "${WORK}/mor.out" MOR \
      MOR_INSERT_PASS MOR_UPDATE_PASS MOR_SNAPSHOT_PASS MOR_RO_PASS MOR_TIMELINE_PASS \
     && grep -q 'dt=2024-01-01' "${WORK}/mor.out"; then
    MOR_OK=1
    echo "[hudi-test] MOR snapshot + read-optimized OK"
  else
    echo "HUDI_MOR_FAIL: marker or partition check failed" >&2
  fi
else
  echo "HUDI_MOR_FAIL: spark-sql exited with error" >&2
  tail -n 80 "${WORK}/mor.out" >&2
fi

[ "${COW_OK}" -eq 1 ] && echo "HUDI_COW_PASS"
[ "${MOR_OK}" -eq 1 ] && echo "HUDI_MOR_PASS"

[ "${COW_OK}" -eq 1 ] && [ "${MOR_OK}" -eq 1 ]
