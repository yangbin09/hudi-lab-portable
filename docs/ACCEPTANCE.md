# 验收报告

- 项目：<https://github.com/yangbin09/hudi-lab-portable>（Public）
- 本地路径：`D:\hudi-lab-portable`
- 验收日期：2026-10-30
- 开发机：Windows 10 Pro 22H2 / Docker Desktop 4.97.0 / Engine 29.9.2 / Compose 5.6.1
- 数据隔离：新项目与旧 `D:\hudi-lab` 完全独立

## 1. 验收结果

| 项目 | 结果 | 依据 |
|---|---|---|
| 现有环境审计 | PASS | `docker ps -a` / `docker inspect` / `docker volume ls`；旧三容器 HEALTHY |
| 新项目目录创建 | PASS | 48 个受控文件，独立 Git 仓库 |
| Spark Dockerfile | PASS | 两阶段构建，构建期下载并校验 Hudi JAR |
| Spark 镜像重新构建 | PASS | 本地构建 + GitHub Actions 构建均成功 |
| Hudi JAR 验证 | PASS | Maven Central SHA256 = `7ade6ae1…d5fda7`，与旧环境 JAR 一致 |
| Hadoop 3.3.6 | PASS | `hdfs version` → Hadoop 3.3.6 |
| Compose 校验 | PASS | `docker compose config --quiet`；YAML 解析通过 |
| NameNode | PASS | healthcheck healthy，Safe Mode OFF |
| DataNode | PASS | healthcheck healthy，Live DataNodes=1 |
| HDFS 文件读写 | PASS | mkdir / put / cat / fsck，Status HEALTHY |
| Spark 访问 HDFS | PASS | Spark SQL 写 Parquet 到 HDFS 并读回 3 行 |
| Hudi COW CRUD | PASS | INSERT / UPDATE / DELETE / SELECT / SHOW PARTITIONS |
| Hudi MOR CRUD | PASS | 快照读 5 行、读优化读非空、4 个 commit 时间 |
| Timeline 验证 | PASS | COW `.commit`=3；MOR `.deltacommit`=5 |
| Base File / Log File | PASS | COW parquet=4；MOR parquet=2 + `.log`=2 |
| Docker 重启持久化 | PASS（容器重建） | `down` + `up` 后 HDFS 标记文件与 Hudi 表数据仍在 |
| Windows bootstrap | PASS | 完整流程 SUCCESS；首次格式化与重复复用均验证 |
| Linux bootstrap | NOT TESTED | 无 Linux 主机；16 个脚本 `bash -n` 全部通过 |
| GitHub 仓库 | PASS | <https://github.com/yangbin09/hudi-lab-portable>（Public） |
| GHCR 镜像发布 | PASS | `ghcr.io/yangbin09/hudi-lab-spark:0.1.1`，匿名可拉取 |
| 新机器拉取镜像 | PASS | 删除本地镜像后由 bootstrap 从 GHCR 拉取并完成全部测试 |
| 原有环境保持完好 | PASS | 旧容器运行中，旧卷存在，COW/MOR 各 5 行可查 |

## 2. 关键实测输出

### 2.1 完整部署（GHCR 镜像）

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

运行中的 Spark 容器镜像：

```
ghcr.io/yangbin09/hudi-lab-spark:0.1.1
sha256:21817c68f09032a3078d742761e6b4f4beace4e9f1ca1cf388ad0cecb8c166ad
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

### 2.4 初始化守卫

销毁后重新部署：

```
[init] 全新空目录，执行首次 hdfs namenode -format
```

再次启动：

```
[init] 检测到已有 NameNode 元数据 (current/VERSION)，跳过格式化。
```

### 2.5 端口冲突

占用 19000 后执行 bootstrap：

```
[FAIL] 宿主机端口已被占用: NN_RPC_PORT=19000。请修改 .env 中的端口，或自行释放端口。脚本不会停止其它容器。
```

退出码 1，未启动/停止任何容器。

### 2.6 destroy 安全确认

- 错误确认串：退出码 1，容器 / 卷 / 网络均未删除。
- 正确确认串 `DELETE HUDI LAB PORTABLE`：只删除本项目 3 容器、4 卷、1 网络。
- 旧 `hudi-namenode` / `hudi-datanode` / `hudi-spark` 全程运行。

### 2.7 GitHub Actions

| 工作流 | 结果 | 链接 |
|---|---|---|
| CI | success | <https://github.com/yangbin09/hudi-lab-portable/actions/runs/41059572430> |
| Release | success | <https://github.com/yangbin09/hudi-lab-portable/actions/runs/41059580167> |

发布标签：`0.1.0`、`sha-0281409bdd4e`。

匿名拉取验证：

```
docker logout ghcr.io
docker pull ghcr.io/yangbin09/hudi-lab-spark:0.1.1
Digest: sha256:21817c68f09032a3078d742761e6b4f4beace4e9f1ca1cf388ad0cecb8c166ad
```

## 3. 开发过程中发现并修复的问题

| 问题 | 现象 | 处理 |
|---|---|---|
| Spark 侧 XML 误用 `#` 注释 | `WstxUnexpectedCharException` | 改为标准 XML 注释 |
| Safe Mode 状态读取错误 | 汇总显示 `safe-mode=unknown` | 单独执行 `dfsadmin -safemode get` |
| 启动顺序错误 | 已有数据时在 DataNode 启动前等 Safe Mode，300 秒超时 | 先启动 DataNode 并等待注册，再等 Safe Mode 关闭 |
| Timeline 断言过严 | 删除行的 commit 不在快照中 | SQL 校验 ≥2，完整数量由 `.hoodie` 目录校验 |
| MOR 被 COW 失败短路 | COW 失败时 MOR 不执行 | 两个测试独立执行、分别汇总 |
| warehouse 目录落到 HDFS | HDFS 根出现 `/workspace` | 显式 `file:///workspace/warehouse` |
| Dockerfile syntax frontend 拉取失败 | Docker Hub `401 Unauthorized` | 移除 `# syntax=` 指令 |
| Windows git 默认 CRLF | `.sh` 进容器报 `$'\r'` | `.gitattributes` 强制 LF；克隆后实测 LF |
| Bash 关联数组带空格键 | 结果汇总静默失效 | 改为无空格键 + 显示名映射 |

## 4. 已知限制 / 未完成事项

1. **Linux 真实部署**：当前开发机为 Windows，Linux 脚本仅完成静态检查。
2. **整机 Docker Desktop 重启**：未单独执行；已验证等价的容器重建 + 命名卷持久化。
3. 单 NameNode / 单 DataNode、复制因子 1、关闭 HDFS 权限检查，仅用于学习环境。
4. 镜像仅 `linux/amd64`，未做 ARM64 适配。
