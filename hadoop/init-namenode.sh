#!/usr/bin/env bash
#
# NameNode 启动守卫（沿用已验证行为）：
#   1. 已有 current/VERSION  -> 直接启动，绝不重新格式化
#   2. 目录为空/不存在       -> 首次 Format，然后启动
#   3. 目录非空但缺 VERSION  -> 报错退出，不自动格式化
#
set -euo pipefail

NN_DIR="${NAMENODE_DATA_DIR:-/data/dfs/name}"

echo "[init] NameNode 数据目录: ${NN_DIR}"

if [ -f "${NN_DIR}/current/VERSION" ]; then
  echo "[init] 检测到已有 NameNode 元数据 (current/VERSION)，跳过格式化。"
else
  if [ -d "${NN_DIR}" ] && [ -n "$(ls -A "${NN_DIR}" 2>/dev/null || true)" ]; then
    echo "[init][ERROR] 目录非空，但缺少 current/VERSION。" >&2
    echo "[init][ERROR] 拒绝自动格式化，避免破坏已有数据。" >&2
    echo "[init][ERROR] 请人工检查: ${NN_DIR}" >&2
    ls -la "${NN_DIR}" >&2 || true
    exit 1
  fi
  echo "[init] 全新空目录，执行首次 hdfs namenode -format"
  hdfs namenode -format -nonInteractive
fi

echo "[init] 启动 NameNode ..."
exec hdfs namenode
