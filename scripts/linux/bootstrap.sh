#!/usr/bin/env bash
# =============================================================
# Hudi Lab Portable —— Linux 一键部署（幂等）
#
#   ./scripts/linux/bootstrap.sh
#   ./scripts/linux/bootstrap.sh --persistence-test
#   ./scripts/linux/bootstrap.sh --skip-tests
# =============================================================
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

PERSISTENCE_TEST=0
SKIP_TESTS=0
TIMEOUT=300

while [ $# -gt 0 ]; do
  case "$1" in
    --persistence-test) PERSISTENCE_TEST=1 ;;
    --skip-tests)       SKIP_TESTS=1 ;;
    --timeout)          shift; TIMEOUT="${1:-300}" ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "未知参数: $1" ;;
  esac
  shift
done

RUN_ID="$(date +%Y%m%d%H%M%S)"
EXIT_CODE=0
declare -A RESULTS=()

find_docker

# ---------------------------------------------------------
section "1/8 检查本机 Docker 环境"
assert_docker_ready
ensure_env_file

EXISTING="$(docker_compose ps -a -q 2>/dev/null | wc -l | tr -d ' ')"
if [ "${EXISTING}" = "0" ]; then
  assert_ports_available
else
  ok "检测到已有部署，跳过端口占用检查（不会重新初始化数据）"
fi

# ---------------------------------------------------------
section "2/8 准备 Spark + Hudi 镜像"
ensure_spark_image

# ---------------------------------------------------------
section "3/8 启动 NameNode"
docker_compose up -d namenode
wait_service_healthy namenode "${TIMEOUT}"

# ---------------------------------------------------------
# Safe Mode 必须等 DataNode 汇报块后才能关闭，不能提前等待
section "4/8 启动 DataNode"
docker_compose up -d datanode
wait_service_healthy datanode "${TIMEOUT}"
wait_live_datanodes 1 "${TIMEOUT}"
wait_safemode_off "${TIMEOUT}"

# ---------------------------------------------------------
section "5/8 启动 Spark"
docker_compose up -d spark
wait_service_healthy spark "${TIMEOUT}"

# ---------------------------------------------------------
if [ "${SKIP_TESTS}" -eq 0 ]; then
  section "6/8 功能冒烟测试"
  info "测试运行 ID: ${RUN_ID}（测试数据位于 /tmp/hudi-lab-portable-test/${RUN_ID}）"

  printf '\n  -> HDFS\n'
  if run_test_script namenode /opt/hudi-lab/tests/test-hdfs.sh "${RUN_ID}"; then
    RESULTS[HDFS_TEST]="PASS"; ok "HDFS Test PASS"
  else
    RESULTS[HDFS_TEST]="FAIL"; EXIT_CODE=1; err "HDFS Test FAIL"
  fi

  printf '\n  -> Spark + HDFS\n'
  if run_test_script spark /opt/hudi-lab/tests/test-spark.sh "${RUN_ID}"; then
    RESULTS[SPARK_TEST]="PASS"; ok "Spark Test PASS"
  else
    RESULTS[SPARK_TEST]="FAIL"; EXIT_CODE=1; err "Spark Test FAIL"
  fi

  printf '\n  -> Hudi COW / MOR\n'
  COW_OK=0; MOR_OK=0
  if run_test_script spark /opt/hudi-lab/tests/test-hudi.sh "${RUN_ID}"; then
    COW_OK=1; MOR_OK=1
  fi
  if ! run_test_script namenode /opt/hudi-lab/tests/verify-hudi-layout.sh "${RUN_ID}"; then
    COW_OK=0; MOR_OK=0
  fi

  if [ "${COW_OK}" -eq 1 ]; then RESULTS[HUDI_COW]="PASS"; ok "Hudi COW PASS"
  else RESULTS[HUDI_COW]="FAIL"; EXIT_CODE=1; err "Hudi COW FAIL"; fi

  if [ "${MOR_OK}" -eq 1 ]; then RESULTS[HUDI_MOR]="PASS"; ok "Hudi MOR PASS"
  else RESULTS[HUDI_MOR]="FAIL"; EXIT_CODE=1; err "Hudi MOR FAIL"; fi

  if [ "${PERSISTENCE_TEST}" -eq 1 ]; then
    printf '\n  -> 容器重建后的数据持久化\n'
    MARKER="hudi-lab-persist-${RUN_ID}"
    docker_compose exec -T namenode bash -c \
      "echo '${MARKER}' | hdfs dfs -put -f - /tmp/hudi-lab-portable-test/${RUN_ID}/persist.txt" >/dev/null

    docker_compose down
    docker_compose up -d
    wait_service_healthy namenode "${TIMEOUT}"
    wait_service_healthy datanode "${TIMEOUT}"
    wait_live_datanodes 1 "${TIMEOUT}"
    wait_safemode_off "${TIMEOUT}"
    wait_service_healthy spark "${TIMEOUT}"

    MARKER_OUT="$(docker_compose exec -T namenode hdfs dfs -cat "/tmp/hudi-lab-portable-test/${RUN_ID}/persist.txt" 2>/dev/null | tr -d '\r' | head -1 || true)"
    if [ "${MARKER_OUT}" = "${MARKER}" ] \
       && run_test_script spark /opt/hudi-lab/tests/test-persistence.sh "${RUN_ID}"; then
      RESULTS[Persistence]="PASS"; ok "Persistence PASS（容器重建后 HDFS 与 Hudi 表均保留）"
    else
      RESULTS[Persistence]="FAIL"; EXIT_CODE=1; err "Persistence FAIL (marker='${MARKER_OUT}')"
    fi
  fi

  printf '\n'
  info "清理本次测试数据（仅 run id 资源）"
  run_test_script spark /opt/hudi-lab/tests/cleanup-hudi.sh "${RUN_ID}" >/dev/null 2>&1 || true
  docker_compose exec -T namenode hdfs dfs -rm -r -f "/tmp/hudi-lab-portable-test/${RUN_ID}" >/dev/null 2>&1 || true
else
  section "6/8 功能冒烟测试（已跳过）"
  RESULTS[HDFS_TEST]="NOT TESTED"
  RESULTS[SPARK_TEST]="NOT TESTED"
  RESULTS[HUDI_COW]="NOT TESTED"
  RESULTS[HUDI_MOR]="NOT TESTED"
fi

# ---------------------------------------------------------
section "7/8 部署状态"
show_summary
if [ ${#RESULTS[@]} -gt 0 ]; then
  for key in HDFS_TEST SPARK_TEST HUDI_COW HUDI_MOR PERSISTENCE; do
    [ -n "${RESULTS[$key]:-}" ] || continue
    case "${key}" in
      HDFS_TEST)   label="HDFS Test" ;;
      SPARK_TEST)  label="Spark Test" ;;
      HUDI_COW)    label="Hudi COW" ;;
      HUDI_MOR)    label="Hudi MOR" ;;
      PERSISTENCE) label="Persistence" ;;
      *)           label="${key}" ;;
    esac
    print_result "${label}" "${RESULTS[$key]}"
  done
  printf '\n'
fi

# ---------------------------------------------------------
section "8/8 完成"
if [ "${EXIT_CODE}" -eq 0 ]; then
  printf '  %sDeployment:   SUCCESS%s\n\n' "${C_GREEN}" "${C_RESET}"
  printf '  常用命令：\n'
  printf '    ./scripts/linux/status.sh            查看状态\n'
  printf '    ./scripts/linux/spark-sql.sh         进入 Spark SQL\n'
  printf '    ./scripts/linux/hdfs.sh dfs -ls /    操作 HDFS\n'
  printf '    ./scripts/linux/down.sh              停止（保留数据）\n\n'
else
  printf '  %sDeployment:   FAILED%s（见上方失败项）\n\n' "${C_RED}" "${C_RESET}"
fi

exit "${EXIT_CODE}"
