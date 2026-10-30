# 验收报告

- 项目：`D:\hudi-lab-portable`
- 验收日期：2026-10-30
- 开发机：Windows 10 Pro 22H2 / Docker Desktop 4.97.0 / Engine 29.9.2 / Compose 5.6.1
- 工作目录：`D:\hudi-lab-portable`（独立于旧 `D:\hudi-lab`）

## 1. 验收结果

| 项目 | 结果 | 依据 |
|---|---|---|
| 现有环境审计 | PASS | `docker ps -a` / `docker inspect` / `docker volume ls`；旧三容器 HEALTHY |
| 新项目目录创建 | PASS | 46 个受控文件，独立 Git 仓库 |
| Spark Dockerfile | PASS | 两阶段构建，构建期下载并校验 Hudi JAR |
| Spark 镜像重新构建 | PASS | `hudi-lab-portable-spark:0.1.0` 构建成功（两次） |
| Hudi JAR 验证 | PASS | Maven Central SHA256 = `7ade6ae1…d5fda7`，与旧环境 JAR 一致 |
| Hadoop 3.3.6 | PASS | `hdfs version` → Hadoop 3.3.6 |
| Compose 校验 | PASS | `docker compose config --quiet`；YAML 解析通过 |
| NameNode | PASS | healthcheck healthy，Safe Mode OFF |
| DataNode | PASS | healthcheck healthy，Live DataNodes=1 |
| HDFS 文件读写 | PASS | mkdir / put / cat / fsck，Status HEALTHY |
| Spark 访问 HDFS | PASS | Spark SQL 写 Parquet 到 HDFS 并读回 3 行，内容一致 |
| Hudi COW CRUD | PASS | INSERT / UPDATE / DELETE / SELECT / SHOW PARTITIONS 全部通过 |
| Hudi MOR CRUD | PASS | 快照读 5 行、读优化读非空、4 个 commit 时间 |
| Timeline 验证 | PASS | COW `.commit`=3；MOR `.deltacommit`=5 |
| Base File / Log File | PASS | COW parquet=4；MOR parquet=2 + `.log`=2 |
| Docker 重启持久化 | PASS（容器重建） | `down` + `up` 后 HDFS 标记文件与 Hudi 表数据仍在 |
| Windows bootstrap | PASS | 完整流程 SUCCESS，含首次格式化与重复复用 |
| Linux bootstrap | NOT TESTED | 无 Linux 主机；仅 `bash -n` 静态检查 16 个脚本全部通过 |
| GitHub 仓库 | 待授权 | 本机 `gh` 未登录，未创建远程仓库 |
| GHCR 镜像发布 | 待授权 | 未推送任何镜像 |
| 新机器拉取镜像 | NOT TESTED | 依赖 GHCR 发布 |
| 原有环境保持完好 | PASS | 旧容器运行中，旧卷存在，COW/MOR 各 5 行可查 |

## 2. 关键实测输出

### 2.1 完整部署

```
NameNode:     HEALTHY
DataNode:     HEALTHY
Spark:        HEALTHY
HDFS Nodes:   live=1  safe-mode=OFF

HDFS Test:     PASS
Spark Test:    PASS
Hudi COW:      PASS
Hudi MOR:      PASS

Deployment:   SUCCESS
```

### 2.2 Hudi 物理文件校验

```
[hudi-layout] COW commits=3 parquet=4
[hudi-layout] MOR deltacommits=5 commits=0 parquet=2 logfiles=2
[hudi-layout] metadata table disabled (no .hoodie/metadata)
HUDI_LAYOUT_PASS
```

### 2.3 持久化

```
PERSISTENCE_PASS
[OK] Persistence PASS（容器重建后 HDFS 与 Hudi 表均保留）
```

### 2.4 首次初始化守卫

销毁后重新部署，NameNode 日志：

```
[init] NameNode 数据目录: /data/dfs/name
[init] 全新空目录，执行首次 hdfs namenode -format
[init] 启动 NameNode ...
```

再次启动（容器重建）：

```
[init] 检测到已有 NameNode 元数据 (current/VERSION)，跳过格式化。
```

### 2.5 destroy 安全确认

- 输入 `WRONG CONFIRMATION`：退出码 1，容器 / 卷 / 网络均未被删除。
- 输入 `DELETE HUDI LAB PORTABLE`：仅删除本项目 3 容器、4 卷、1 网络。
- 旧 `hudi-namenode` / `hudi-datanode` / `hudi-spark` 全程保持运行。

## 3. 开发过程中发现并修复的问题

| 问题 | 现象 | 处理 |
|---|---|---|
| Spark 侧 XML 误用 `#` 注释 | `WstxUnexpectedCharException: Unexpected character '#'` | 改为标准 XML 注释 |
| Safe Mode 状态读取错误 | 汇总显示 `safe-mode=unknown` | 单独执行 `dfsadmin -safemode get` |
| Timeline 断言过严 | COW 只看到 2 个 commit 时间 | 删除行的 commit 不在快照中；改为 SQL 校验 ≥2，完整数量由 `.hoodie` 目录校验 |
| MOR 被 COW 失败短路 | COW 失败时 MOR 完全不执行 | 两个测试独立执行、分别汇总 |
| warehouse 目录落到 HDFS | HDFS 根目录出现 `/workspace` | 改为 `file:///workspace/warehouse`，使用命名卷 |
| Dockerfile syntax frontend 拉取失败 | `401 Unauthorized` from Docker Hub | 移除 `# syntax=` 指令，减少外部依赖 |
| Windows git 默认 CRLF | `.sh` 挂载进容器会报 `$'\r'` | 增加 `.gitattributes` 强制 LF |

## 4. 未完成事项

1. **GitHub 仓库创建与推送**：需要 GitHub 账户授权（`gh auth login`）及提交者姓名/邮箱。
2. **GHCR 首次发布**：依赖第 1 项；发布 `ghcr.io/<owner>/hudi-lab-spark:0.1.0`。
3. **Linux 真实部署**：当前开发机为 Windows，Linux 脚本仅完成静态检查。
4. **整机 Docker Desktop 重启**：未单独执行；已验证等价的容器重建 + 命名卷持久化。
