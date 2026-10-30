#!/usr/bin/env bash
# =============================================================
# Hudi Lab Portable —— 只读诊断（不会删除或修改任何内容）
# =============================================================
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

FAILED=0

check() {
  local name="$1" warn_only="${2:-0}"
  shift 2
  if "$@" >/dev/null 2>&1; then
    ok "${name}"
  else
    if [ "${warn_only}" = "1" ]; then
      warn "${name} —— 检查未通过"
    else
      err "${name} —— 检查未通过"
      FAILED=$((FAILED + 1))
    fi
  fi
}

check_note() {
  local name="$1" note="$2" warn_only="${3:-0}"
  if [ "${warn_only}" = "1" ]; then warn "${name} —— ${note}"; else err "${name} —— ${note}"; FAILED=$((FAILED + 1)); fi
}

c_docker()      { command -v docker >/dev/null 2>&1; }
c_engine()      { docker version --format '{{.Server.Version}}' >/dev/null 2>&1; }
c_compose()     { docker compose version --short >/dev/null 2>&1; }
c_linux_mode()  { [ "$(docker info --format '{{.OSType}}' 2>/dev/null)" = "linux" ]; }
c_compose_yml() { [ -f "${COMPOSE_FILE}" ]; }
c_env()         { [ -f "${ENV_FILE}" ]; }
c_config()      { docker_compose config --quiet; }

c_xml() {
  local f
  for f in hadoop/core-site.xml hadoop/hdfs-site.xml spark/hadoop-conf/core-site.xml spark/hadoop-conf/hdfs-site.xml; do
    [ -f "${REPO_ROOT}/${f}" ] || return 1
    if command -v python3 >/dev/null 2>&1; then
      python3 -c 'import sys,xml.etree.ElementTree as E; E.parse(sys.argv[1])' "${REPO_ROOT}/${f}" || return 1
    elif command -v xmllint >/dev/null 2>&1; then
      xmllint --noout "${REPO_ROOT}/${f}" || return 1
    else
      grep -q '<configuration>' "${REPO_ROOT}/${f}" || return 1
    fi
  done
}

c_hadoop_image() { docker image inspect apache/hadoop:3.3.6 >/dev/null 2>&1; }

c_spark_image() {
  local image; image="$(env_value SPARK_IMAGE)"; [ -n "${image}" ] || image="hudi-lab-portable-spark:0.1.0"
  docker image inspect "${image}" >/dev/null 2>&1
}

c_volumes() {
  local v
  for v in hudi-lab-portable_namenode-data hudi-lab-portable_datanode-data hudi-lab-portable_spark-warehouse hudi-lab-portable_spark-metastore; do
    docker volume inspect "${v}" >/dev/null 2>&1 || return 1
  done
}

c_network() { docker network inspect hudi-lab-portable_default >/dev/null 2>&1; }

c_service() {
  local service="$1"
  [ "$(service_state "${service}")" = "running" ] && [ "$(service_health "${service}")" = "healthy" ]
}

c_hdfs_ls()   { docker_compose exec -T namenode hdfs dfs -ls / >/dev/null 2>&1; }
c_hdfs_live() { docker_compose exec -T namenode hdfs dfsadmin -report 2>/dev/null | grep -q 'Live datanodes (1)'; }
c_hdfs_safe() { docker_compose exec -T namenode hdfs dfsadmin -safemode get 2>/dev/null | grep -q 'Safe mode is OFF'; }
c_spark_run() { docker_compose exec -T spark /opt/spark/bin/spark-submit --version >/dev/null 2>&1; }

section "Hudi Lab Portable 诊断（只读）"

check 'docker 命令可用' 0 c_docker
check 'Docker Engine 运行中' 0 c_engine
check 'Docker Compose 可用' 0 c_compose
check 'Linux Containers 模式' 0 c_linux_mode

check 'compose.yaml 存在' 0 c_compose_yml
check '.env 存在' 0 c_env
check 'Hadoop XML 配置可解析' 0 c_xml
check 'Compose 配置可解析' 0 c_config

check 'Hadoop 镜像存在 (apache/hadoop:3.3.6)' 0 c_hadoop_image
check 'Spark + Hudi 镜像存在' 0 c_spark_image

check '项目数据卷齐全' 1 c_volumes
check '项目网络存在' 1 c_network

check 'NameNode 运行且健康' 0 c_service namenode
check 'DataNode 运行且健康' 0 c_service datanode
check 'Spark 运行且健康' 0 c_service spark

check 'HDFS 可读（dfs -ls /）' 0 c_hdfs_ls
check 'HDFS Live DataNodes = 1' 0 c_hdfs_live
check 'HDFS Safe Mode 已关闭' 0 c_hdfs_safe
check 'Spark 可执行（spark-submit --version）' 0 c_spark_run

printf '\n'
if [ "${FAILED}" -eq 0 ]; then
  printf '  %sDoctor: PASS（未执行任何写操作）%s\n\n' "${C_GREEN}" "${C_RESET}"
  exit 0
else
  printf '  %sDoctor: %s 项失败（未执行任何写操作）%s\n\n' "${C_RED}" "${FAILED}" "${C_RESET}"
  exit 1
fi
