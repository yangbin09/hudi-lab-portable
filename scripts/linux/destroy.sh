#!/usr/bin/env bash
# =============================================================
# Hudi Lab Portable —— 删除本项目的容器、网络与数据卷（不可恢复）
#
# 只操作 Compose 项目 hudi-lab-portable。
# 不使用 docker volume prune / docker system prune。
# 不会删除旧的 hudi-lab 环境。
# =============================================================
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

find_docker

section "即将删除的 hudi-lab-portable 资源"
info "Compose 项目: hudi-lab-portable"
printf '\n'

info "容器:"
docker_compose ps -a --format '    {{.Name}}  {{.Status}}'

info "数据卷:"
docker volume ls --filter 'name=hudi-lab-portable' --format '    {{.Name}}'

info "网络:"
docker network ls --filter 'name=hudi-lab-portable' --format '    {{.Name}}'

printf '\n'
printf '  %s这会永久删除 HDFS 数据、Hudi 表、Spark warehouse 与 Derby 元数据。%s\n' "${C_YELLOW}" "${C_RESET}"
printf '  %s旧 hudi-lab 环境（hudi-namenode / hudi-datanode / hudi-spark）不受影响。%s\n\n' "${C_YELLOW}" "${C_RESET}"

printf '  请输入完整确认字符串: DELETE HUDI LAB PORTABLE\n  > '
read -r ANSWER

if [ "${ANSWER}" != "DELETE HUDI LAB PORTABLE" ]; then
  printf '\n'
  warn "确认字符串不匹配，已退出，未删除任何内容。"
  exit 1
fi

printf '\n'
docker_compose down --volumes --remove-orphans

ok "容器、网络与数据卷已删除"
printf '\n  重新部署: ./scripts/linux/bootstrap.sh\n\n'
