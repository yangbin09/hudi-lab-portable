#!/usr/bin/env bash
# =============================================================
# 进入 Hudi Lab Portable 的 Spark SQL（转发参数到 spark-sql）
#
#   ./scripts/linux/spark-sql.sh
#   ./scripts/linux/spark-sql.sh -f /workspace/sql/cow-test.sql
#   ./scripts/linux/spark-sql.sh -e "SHOW DATABASES"
# =============================================================
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

find_docker

if [ "$(service_state spark)" != "running" ]; then
  err "Spark 容器未运行。请先执行 ./scripts/linux/up.sh"
  exit 1
fi

if [ $# -gt 0 ]; then
  # 非交互：-e / -f 等参数
  exec docker_compose exec -T spark /opt/spark/bin/spark-sql "$@"
else
  # 交互式会话（需要 TTY）
  exec docker_compose exec spark /opt/spark/bin/spark-sql
fi
