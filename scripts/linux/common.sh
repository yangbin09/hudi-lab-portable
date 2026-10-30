#!/usr/bin/env bash
# =============================================================
# Hudi Lab Portable —— Linux 脚本公共函数
# 需要 Bash 4+、Docker Engine、Docker Compose Plugin。
# =============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE_FILE="${REPO_ROOT}/compose.yaml"
ENV_FILE="${REPO_ROOT}/.env"

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'; C_CYAN=$'\033[36m'; C_GRAY=$'\033[90m'
else
  C_RESET=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_CYAN=''; C_GRAY=''
fi

section() { printf '\n%s== %s ==%s\n' "${C_CYAN}" "$*" "${C_RESET}"; }
ok()      { printf '  %s[OK]%s   %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
warn()    { printf '  %s[WARN]%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
err()     { printf '  %s[FAIL]%s %s\n' "${C_RED}" "${C_RESET}" "$*"; }
info()    { printf '  %s\n' "$*"; }

die() {
  printf '\n  %s[FAIL]%s %s\n\n' "${C_RED}" "${C_RESET}" "$*" >&2
  exit 1
}

docker_compose() {
  docker compose --project-directory "${REPO_ROOT}" -f "${COMPOSE_FILE}" "$@"
}

find_docker() {
  command -v docker >/dev/null 2>&1 || die "未找到 docker 命令。请安装 Docker Engine 与 Docker Compose Plugin。"
}

env_value() {
  local key="$1"
  [ -f "${ENV_FILE}" ] || return 0
  grep -E "^${key}=" "${ENV_FILE}" | tail -n 1 | cut -d= -f2- | tr -d '\r'
}

ensure_env_file() {
  if [ ! -f "${ENV_FILE}" ]; then
    [ -f "${REPO_ROOT}/.env.example" ] || die "缺少 .env.example，仓库不完整。"
    cp "${REPO_ROOT}/.env.example" "${ENV_FILE}"
    ok "已根据 .env.example 创建 .env"
  else
    ok ".env 已存在（复用）"
  fi
}

assert_docker_ready() {
  local server_version compose_version os_type mem_raw mem_bytes mem_gb

  server_version="$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)"
  [ -n "${server_version}" ] || die "Docker Engine 未就绪。请启动 Docker 服务（systemctl start docker）。"
  ok "Docker Engine ${server_version}"

  compose_version="$(docker compose version --short 2>/dev/null || true)"
  [ -n "${compose_version}" ] || die "Docker Compose Plugin 不可用（需要 docker compose v2+）。"
  ok "Docker Compose ${compose_version}"

  os_type="$(docker info --format '{{.OSType}}' 2>/dev/null || true)"
  [ "${os_type}" = "linux" ] || die "Docker 不是 Linux 容器模式 (OSType=${os_type})。"
  ok "Docker 运行模式: linux containers"

  mem_raw="$(docker info --format '{{.MemTotal}}' 2>/dev/null || true)"
  if [[ "${mem_raw}" =~ ^[0-9]+$ ]]; then
    mem_gb=$(( mem_raw / 1024 / 1024 / 1024 ))
    [ "${mem_gb}" -ge 4 ] || die "Docker 可用内存仅 ${mem_gb} GB，至少需要 4 GB（建议 8 GB 以上）。"
    ok "Docker 可用内存: ${mem_gb} GB"
  else
    warn "无法读取 Docker 可用内存"
  fi

  local free_gb
  free_gb="$(df -Pk "${REPO_ROOT}" | awk 'NR==2 {printf "%d", $4/1024/1024}')"
  if [ -n "${free_gb}" ] && [ "${free_gb}" -lt 5 ]; then
    warn "项目所在磁盘剩余空间仅 ${free_gb} GB（建议 10 GB 以上）"
  else
    ok "项目所在磁盘剩余空间: ${free_gb} GB"
  fi
}

listening_ports() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltnH 2>/dev/null | awk '{print $4}' | awk -F: '{print $NF}'
  elif command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | awk 'NR>2 {print $4}' | awk -F: '{print $NF}'
  fi
}

assert_ports_available() {
  local ports listening conflicts=() name value
  local nn_rpc nn_web dn_web

  nn_rpc="$(env_value NN_RPC_PORT)"; nn_web="$(env_value NN_WEB_PORT)"; dn_web="$(env_value DN_WEB_PORT)"
  [ -n "${nn_rpc}" ] || die ".env 缺少 NN_RPC_PORT"
  [ -n "${nn_web}" ] || die ".env 缺少 NN_WEB_PORT"
  [ -n "${dn_web}" ] || die ".env 缺少 DN_WEB_PORT"

  for name in NN_RPC_PORT NN_WEB_PORT DN_WEB_PORT; do
    value="$(env_value "${name}")"
    [[ "${value}" =~ ^[0-9]+$ ]] || die ".env 中 ${name} 不是合法端口: ${value}"
    [ "${value}" -ge 1 ] && [ "${value}" -le 65535 ] || die ".env 中 ${name} 越界: ${value}"
  done

  [ "${nn_rpc}" != "${nn_web}" ] && [ "${nn_rpc}" != "${dn_web}" ] && [ "${nn_web}" != "${dn_web}" ] \
    || die "端口配置重复: NN_RPC_PORT=${nn_rpc} NN_WEB_PORT=${nn_web} DN_WEB_PORT=${dn_web}"

  listening="$(listening_ports || true)"
  if [ -z "${listening}" ]; then
    warn "无法枚举宿主机监听端口（缺少 ss/netstat），跳过端口占用检查"
    return 0
  fi

  for name in NN_RPC_PORT NN_WEB_PORT DN_WEB_PORT; do
    value="$(env_value "${name}")"
    if printf '%s\n' "${listening}" | grep -qx "${value}"; then
      conflicts+=("${name}=${value}")
    fi
  done

  if [ ${#conflicts[@]} -gt 0 ]; then
    die "宿主机端口已被占用: ${conflicts[*]}。请修改 .env 或自行释放端口。脚本不会停止其它容器。"
  fi
  ok "端口可用: RPC=${nn_rpc} NN-UI=${nn_web} DN-UI=${dn_web}"
}

service_id() {
  docker compose --project-directory "${REPO_ROOT}" -f "${COMPOSE_FILE}" ps -q "$1" 2>/dev/null | head -n 1
}

service_state() {
  local id; id="$(service_id "$1")"
  if [ -z "${id}" ]; then echo "missing"; else docker inspect -f '{{.State.Status}}' "${id}" 2>/dev/null || echo "missing"; fi
}

service_health() {
  local id; id="$(service_id "$1")"
  if [ -z "${id}" ]; then echo "unknown"; else docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${id}" 2>/dev/null || echo "unknown"; fi
}

show_service_logs() {
  local service="$1" tail="${2:-40}"
  printf '  --- %s 最近 %s 行日志 ---\n' "${service}" "${tail}" >&2
  docker compose --project-directory "${REPO_ROOT}" -f "${COMPOSE_FILE}" logs --tail "${tail}" "${service}" >&2 || true
}

wait_service_healthy() {
  local service="$1" timeout="${2:-300}" deadline state health id
  deadline=$(( $(date +%s) + timeout ))
  while [ "$(date +%s)" -lt "${deadline}" ]; do
    id="$(service_id "${service}")"
    if [ -n "${id}" ]; then
      state="$(docker inspect -f '{{.State.Status}}' "${id}" 2>/dev/null || true)"
      health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${id}" 2>/dev/null || true)"
      if [ "${state}" = "running" ] && { [ "${health}" = "healthy" ] || [ "${health}" = "none" ]; }; then
        ok "${service} 已就绪 (health=${health})"
        return 0
      fi
      if [ "${state}" = "exited" ] || [ "${state}" = "dead" ]; then
        show_service_logs "${service}"
        die "${service} 启动失败 (state=${state})"
      fi
    fi
    sleep 3
  done
  show_service_logs "${service}"
  die "${service} 在 ${timeout} 秒内未就绪"
}

wait_safemode_off() {
  local timeout="${1:-180}" deadline out
  deadline=$(( $(date +%s) + timeout ))
  while [ "$(date +%s)" -lt "${deadline}" ]; do
    out="$(docker_compose exec -T namenode hdfs dfsadmin -safemode get 2>/dev/null || true)"
    if printf '%s' "${out}" | grep -q 'Safe mode is OFF'; then
      ok "HDFS Safe Mode 已关闭"
      return 0
    fi
    sleep 3
  done
  die "HDFS Safe Mode 在 ${timeout} 秒内未关闭"
}

wait_live_datanodes() {
  local expected="${1:-1}" timeout="${2:-180}" deadline out
  deadline=$(( $(date +%s) + timeout ))
  while [ "$(date +%s)" -lt "${deadline}" ]; do
    out="$(docker_compose exec -T namenode hdfs dfsadmin -report 2>/dev/null || true)"
    if printf '%s' "${out}" | grep -q "Live datanodes (${expected})"; then
      ok "HDFS Live DataNodes = ${expected}"
      return 0
    fi
    sleep 3
  done
  die "HDFS Live DataNodes 在 ${timeout} 秒内未达到 ${expected}"
}

ensure_spark_image() {
  local image; image="$(env_value SPARK_IMAGE)"
  [ -n "${image}" ] || image="hudi-lab-portable-spark:0.1.0"

  if docker image inspect "${image}" >/dev/null 2>&1; then
    ok "Spark 镜像已存在: ${image}"
    return 0
  fi

  case "${image}" in
    ghcr.io/*)
      info "从镜像仓库拉取: ${image}"
      if ! docker_compose pull spark; then
        docker image inspect "${image}" >/dev/null 2>&1 \
          || die "拉取 ${image} 失败。若镜像为私有，请先执行: docker login ghcr.io"
      fi
      ok "镜像已就绪: ${image}"
      ;;
    *)
      info "本地构建镜像: ${image}"
      docker_compose build spark || die "Spark 镜像构建失败"
      ok "镜像构建完成: ${image}"
      ;;
  esac
}

run_test_script() {
  # $1=service $2=script path $3..=args
  local service="$1" script="$2"; shift 2
  docker_compose exec -T "${service}" bash "${script}" "$@"
}

show_summary() {
  local docker_version compose_version hadoop_version spark_version hudi_version
  local nn_state nn_health dn_state dn_health sp_state sp_health report live safe nn_port

  docker_version="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo unknown)"
  compose_version="$(docker compose version --short 2>/dev/null || echo unknown)"

  hadoop_version="$(docker_compose exec -T namenode hdfs version 2>/dev/null | grep -oE 'Hadoop [0-9][0-9.]*' | head -1 | awk '{print $2}' || true)"
  [ -n "${hadoop_version}" ] || hadoop_version="unknown"

  spark_version="$(docker_compose exec -T spark /opt/spark/bin/spark-submit --version 2>&1 | grep -oE 'version [0-9][0-9.]*' | head -1 | awk '{print $2}' || true)"
  [ -n "${spark_version}" ] || spark_version="unknown"

  hudi_version="$(docker_compose exec -T spark bash -c 'ls /opt/hudi/*.jar 2>/dev/null' 2>/dev/null | grep -oE 'bundle_2\.12-[0-9.]+\.jar' | head -1 | sed -E 's/bundle_2\.12-([0-9.]+)\.jar/\1/' || true)"
  [ -n "${hudi_version}" ] || hudi_version="unknown"

  nn_state="$(service_state namenode)"; nn_health="$(service_health namenode)"
  dn_state="$(service_state datanode)"; dn_health="$(service_health datanode)"
  sp_state="$(service_state spark)";    sp_health="$(service_health spark)"

  report="$(docker_compose exec -T namenode hdfs dfsadmin -report 2>/dev/null || true)"
  live="$(printf '%s' "${report}" | grep -oE 'Live datanodes \([0-9]+\)' | grep -oE '[0-9]+' | head -1 || true)"
  [ -n "${live}" ] || live="0"
  if printf '%s' "${report}" | grep -q 'Safe mode is ON'; then safe="ON"; else safe="OFF"; fi

  nn_port="$(env_value NN_WEB_PORT)"; [ -n "${nn_port}" ] || nn_port="19870"

  printf '\n  Hudi Lab Portable\n\n'
  printf '  Docker:       %s / Compose %s\n' "${docker_version}" "${compose_version}"
  printf '  Hadoop:       %s\n' "${hadoop_version}"
  printf '  Spark:        %s\n' "${spark_version}"
  printf '  Hudi:         %s\n\n' "${hudi_version}"
  printf '  NameNode:     %s\n' "$(format_state "${nn_state}" "${nn_health}")"
  printf '  DataNode:     %s\n' "$(format_state "${dn_state}" "${dn_health}")"
  printf '  Spark:        %s\n' "$(format_state "${sp_state}" "${sp_health}")"
  printf '  HDFS Nodes:   live=%s  safe-mode=%s\n' "${live}" "${safe}"
  printf '  NameNode UI:  http://127.0.0.1:%s\n\n' "${nn_port}"
}

format_state() {
  local state="$1" health="$2"
  if [ "${state}" = "missing" ]; then echo "MISSING"; return; fi
  if [ "${state}" != "running" ]; then echo "${state^^}"; return; fi
  case "${health}" in
    healthy) echo "HEALTHY" ;;
    starting) echo "STARTING" ;;
    none) echo "RUNNING" ;;
    *) echo "${health^^}" ;;
  esac
}

print_result() {
  local name="$1" value="$2" color="${C_GREEN}"
  case "${value}" in
    PASS) color="${C_GREEN}" ;;
    FAIL) color="${C_RED}" ;;
    *) color="${C_YELLOW}" ;;
  esac
  printf '  %-14s %s%s%s\n' "${name}:" "${color}" "${value}" "${C_RESET}"
}
