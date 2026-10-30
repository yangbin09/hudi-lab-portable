#!/usr/bin/env bash
# =============================================================
# Hudi Lab Portable —— 停止并移除容器，保留所有数据卷
# =============================================================
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

find_docker
section "停止 Hudi Lab Portable"

docker_compose down

ok "容器与项目网络已移除"
ok "数据卷保留：namenode-data / datanode-data / spark-warehouse / spark-metastore"
printf '\n  重新启动: ./scripts/linux/up.sh\n'
printf '  彻底删除: ./scripts/linux/destroy.sh\n\n'
