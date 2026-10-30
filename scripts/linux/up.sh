#!/usr/bin/env bash
# =============================================================
# Hudi Lab Portable —— 启动全部服务（幂等，不删除数据）
# =============================================================
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

TIMEOUT=300
[ $# -ge 1 ] && TIMEOUT="${1}"

find_docker
section "启动 Hudi Lab Portable"
assert_docker_ready
ensure_env_file
ensure_spark_image

docker_compose up -d
wait_service_healthy namenode "${TIMEOUT}"
wait_service_healthy datanode "${TIMEOUT}"
wait_live_datanodes 1 "${TIMEOUT}"
wait_safemode_off "${TIMEOUT}"
wait_service_healthy spark "${TIMEOUT}"

show_summary
