#!/usr/bin/env bash
# =============================================================
# Hudi Lab Portable —— 查看部署状态
# =============================================================
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

find_docker

if [ -z "$(service_id namenode)" ]; then
  printf '\n'
  warn "Hudi Lab Portable 尚未部署或容器已移除。"
  printf '  首次部署: ./scripts/linux/bootstrap.sh\n\n'
  exit 1
fi

show_summary

section "资源"
info "Docker Volumes:"
docker volume ls --filter 'name=hudi-lab-portable' --format '    {{.Name}}'

info "Docker Network:"
docker network ls --filter 'name=hudi-lab-portable' --format '    {{.Name}}  {{.Driver}}'

IDS="$(docker_compose ps -q 2>/dev/null | tr '\n' ' ')"
if [ -n "${IDS// /}" ]; then
  info "容器资源占用:"
  # shellcheck disable=SC2086
  docker stats --no-stream --format '    {{.Name}}  CPU={{.CPUPerc}}  MEM={{.MemUsage}}' ${IDS}
fi
printf '\n'
