#!/usr/bin/env bash
# =============================================================
# 在 NameNode 容器内执行 hdfs 命令（宿主机无需安装 Hadoop）
#
#   ./scripts/linux/hdfs.sh dfs -ls /
#   ./scripts/linux/hdfs.sh dfs -mkdir -p /warehouse
#   ./scripts/linux/hdfs.sh dfs -put ./transfer/test.csv /datasets/
#   ./scripts/linux/hdfs.sh dfsadmin -report
#
# 位于 <repo>/transfer 下的绝对路径会自动映射为 /transfer/...
# =============================================================
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

find_docker

if [ $# -eq 0 ]; then
  cat <<'EOF'

用法: ./scripts/linux/hdfs.sh <command> [args...]

  ./scripts/linux/hdfs.sh dfs -ls /
  ./scripts/linux/hdfs.sh dfs -mkdir -p /warehouse
  ./scripts/linux/hdfs.sh dfs -put ./transfer/test.csv /datasets/
  ./scripts/linux/hdfs.sh dfsadmin -report
  ./scripts/linux/hdfs.sh fsck / -files -blocks

EOF
  exit 0
fi

if [ "$(service_state namenode)" != "running" ]; then
  err "NameNode 容器未运行。请先执行 ./scripts/linux/up.sh"
  exit 1
fi

TRANSFER_WIN="${REPO_ROOT}/transfer"
ARGS=()

for arg in "$@"; do
  if [[ "${arg}" == /* ]]; then
    ARGS+=("${arg}")
    continue
  fi
  if [[ "${arg}" == ./* || "${arg}" == ../* ]]; then
    abs="$(cd "$(dirname "${arg}")" 2>/dev/null && pwd)/$(basename "${arg}")" || abs="${arg}"
  elif [ -e "${arg}" ]; then
    abs="$(cd "$(dirname "${arg}")" && pwd)/$(basename "${arg}")"
  else
    abs="${arg}"
  fi

  case "${abs}" in
    "${TRANSFER_WIN}"/*)
      rel="${abs#"${TRANSFER_WIN}"/}"
      ARGS+=("/transfer/${rel}")
      ;;
    *)
      ARGS+=("${arg}")
      ;;
  esac
done

exec docker_compose exec -T namenode hdfs "${ARGS[@]}"
