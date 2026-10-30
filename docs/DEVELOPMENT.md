# 开发与设计说明

## 1. 目标与非目标

**目标**：一套只包含 3 个容器（NameNode / DataNode / Spark）的 Hudi 单机实验环境，
可通过 Git + Docker 镜像仓库分发，Windows / Linux 一条命令部署，数据持久化，可重复销毁重建。

**非目标**：生产化、多节点 HDFS、YARN、Kubernetes、Hive Metastore Server、
多架构镜像、数据迁移、备份系统、Web 管理后台。

## 2. 架构

```
宿主机 (Windows / Linux)
└── Docker
    └── network: hudi-lab-portable_default
        ├── namenode  (apache/hadoop:3.3.6)   RPC 9000 · UI 9870
        ├── datanode  (apache/hadoop:3.3.6)   data 9866 · IPC 9867 · UI 9864
        └── spark     (hudi-lab-spark:0.1.0)  Spark 3.3.1 / Hudi 0.15.0 / Java 11
```

- Spark 以 `local[*]` 运行，不引入 YARN；
- 容器间只用 Docker 内置 DNS：`namenode` / `datanode`；
- Compose 项目名固定为 `hudi-lab-portable`，网络和卷不与其它项目共享；
- 不使用 `container_name`，便于 Compose 管理与并行项目共存。

## 3. 版本锁定

| 组件 | 版本 | 来源 |
|---|---|---|
| Spark | 3.3.1 | `apache/spark:3.3.1` |
| Hudi | 0.15.0 | Maven Central `hudi-spark3.3-bundle_2.12` |
| Hadoop | 3.3.6 | `apache/hadoop:3.3.6` |
| Java | 11 | 继承自 Spark 基础镜像 |

Hudi JAR 在镜像构建时下载，并强制校验：

```
SHA256 = 7ade6ae19a634f94e1633781630d991b2278fe19271913c5a4a7a652b9d5fda7
```

该校验值与已验证的旧环境 JAR 完全一致。JAR 不进入 Git（`.gitignore` 忽略 `*.jar`）。

Dockerfile 采用两阶段构建：`alpine` 阶段下载并校验，最终镜像只 `COPY` JAR，
不把 `curl` 等构建工具留在运行镜像里，也不依赖宿主机已有文件。

## 4. 为什么不升级 Hadoop 客户端

Spark 3.3.1 自带 `hadoop-client 3.3.2`，Hudi 0.15.0 bundle 内部含 HBase 相关依赖。
在本环境读取 Hudi Metadata Table 时会触发：

```
NoSuchMethodError: org.apache.hadoop.hdfs.client.HdfsDataInputStream.getReadStatistics
```

旧环境通过关闭 Metadata Table 与 Hive Sync 完成了 COW / MOR 全流程验证。
新项目沿用该已验证配置，**不**为了“更规范”而升级依赖或打开 Metadata Table：

```properties
hoodie.metadata.enable=false
hoodie.datasource.hive_sync.enable=false
```

## 5. HDFS 初始化守卫

`hadoop/init-namenode.sh` 每次容器启动都会判断：

| 状态 | 行为 |
|---|---|
| `current/VERSION` 存在 | 直接启动，**绝不格式化** |
| 目录为空或不存在 | 首次 `hdfs namenode -format` |
| 目录非空但无 `VERSION` | 报错退出，不自动清空 |

这样 `bootstrap` 可以安全地重复执行，也不会因为误操作丢失 HDFS 元数据。

## 6. 持久化

| 卷 | 挂载点 |
|---|---|
| `namenode-data` → `hudi-lab-portable_namenode-data` | `/data` |
| `datanode-data` → `hudi-lab-portable_datanode-data` | `/data` |
| `spark-warehouse` → `hudi-lab-portable_spark-warehouse` | `/workspace/warehouse` |
| `spark-metastore` → `hudi-lab-portable_spark-metastore` | `/workspace/metastore` |

Spark 的 Derby 元数据通过
`spark.driver.extraJavaOptions=-Dderby.system.home=/workspace/metastore`
写入命名卷；`spark.sql.warehouse.dir=file:///workspace/warehouse` 明确使用本地卷，
避免默认落到 HDFS。

## 7. 测试设计

测试脚本运行在容器内，宿主机只需要 Docker，不需要 Bash（Windows 也能跑）。

| 脚本 | 运行位置 | 验证内容 |
|---|---|---|
| `tests/test-hdfs.sh` | namenode | mkdir / put / cat / ls / report / fsck |
| `tests/test-spark.sh` | spark | Spark SQL 写 HDFS Parquet 并读回 |
| `tests/test-hudi.sh` | spark | COW / MOR 的 CRUD、快照读、读优化读、分区、时间线 |
| `tests/verify-hudi-layout.sh` | namenode | `.hoodie` 下的 commit / deltacommit、parquet、`.log.*` |
| `tests/test-persistence.sh` | spark | 容器重建后 Hudi 表仍可查询 |
| `tests/cleanup-hudi.sh` | spark | 只删除本次 run id 的表 |

设计要点：

- SQL 模板用 `__RUN_ID__` 占位符，运行期替换，路径与表名天然隔离；
- 所有断言都检查真实产物，不硬编码 MOR 读优化行数；
- 失败信息保留完整 Spark 日志尾部，便于定位；
- COW 与 MOR 互不短路：一个失败仍会执行另一个并分别报告。

## 8. 部署脚本

Windows 与 Linux 共用同一份 `compose.yaml`，脚本只负责编排：

1. 环境检查（Docker / Compose / Linux 模式 / 内存 / 磁盘 / 端口）；
2. `.env` 初始化；
3. 镜像：本地存在则复用，GHCR 镜像缺失才 pull，本地镜像缺失才 build；
4. 分阶段启动并等待 healthcheck，而不是只看容器 Running；
5. 等 Safe Mode 关闭、Live DataNodes=1；
6. 运行冒烟测试；
7. 汇总真实结果。

PowerShell 脚本：

- 兼容 5.1，文件保存为 UTF-8 BOM；
- 自动探测 Docker Desktop 的 per-user 安装路径（`%LOCALAPPDATA%\Programs\DockerDesktop\resources\bin`）；
- 端口检查使用系统 TCP 监听表，不依赖 `netstat` 输出格式。

Bash 脚本：

- `set -euo pipefail`；
- 使用 `ss` / `netstat` 检测端口，两者都没有时给出警告并跳过；
- 不修改防火墙，不把端口绑定到 `0.0.0.0`。

## 9. CI

`.github/workflows/ci.yml`：

- 检查是否误提交 JAR / `.env` / token；
- `docker compose config` 校验；
- 四个 Hadoop/Spark XML 解析 + `fs.defaultFS` 断言；
- 版本固定值断言（Spark 3.3.1、Hudi 0.15.0、Hadoop 3.3.6、无 `latest`）；
- 所有 shell 脚本 `bash -n`；
- 所有 Windows 脚本用 PowerShell Parser 校验语法；
- buildx 构建镜像并在容器内复核 JAR SHA256、Spark 版本；
- 启动 NameNode + DataNode，做一次真实 HDFS 写入/读取。

## 10. 发布

`.github/workflows/release.yml`：

- 由 `v*` Tag 触发；
- `permissions: contents: read, packages: write`；
- 使用 `GITHUB_TOKEN` 登录 GHCR；
- 推送 `ghcr.io/<owner>/hudi-lab-spark:<version>` 与 `:sha-<12位>`；
- 不使用 `latest`；
- 在 Job Summary 输出 digest 与部署用 `SPARK_IMAGE` 值。

首个正式版本 `v0.1.0` 已发布：

| 项目 | 值 |
|---|---|
| 镜像 | `ghcr.io/yangbin09/hudi-lab-spark:0.1.0` |
| Git SHA 标签 | `sha-7a1a4889c79e` |
| Digest | `sha256:a495f3641685e1c11410879fcda1e48deeea516bc8eebb7e76ec0d9edfb2b3c0` |
| 可见性 | public（匿名可拉取） |
| Release Run | <https://github.com/yangbin09/hudi-lab-portable/actions/runs/41056790911> |
| CI Run | <https://github.com/yangbin09/hudi-lab-portable/actions/runs/41056646690> |

部署使用固定版本：

```dotenv
SPARK_IMAGE=ghcr.io/yangbin09/hudi-lab-spark:0.1.0
```

已验证：删除本地镜像后执行 `bootstrap` 会从 GHCR 拉取并完成全部测试；
`docker logout ghcr.io` 后仍可匿名拉取。

## 11. 本地开发流程

```powershell
# 修改配置 / SQL / 测试后
docker compose build spark
docker compose up -d
.\scripts\windows\bootstrap.ps1 -SkipTests

# 只跑测试
docker compose exec -T namenode bash /opt/hudi-lab/tests/test-hdfs.sh 1
docker compose exec -T spark    bash /opt/hudi-lab/tests/test-spark.sh 1
docker compose exec -T spark    bash /opt/hudi-lab/tests/test-hudi.sh 1
docker compose exec -T namenode bash /opt/hudi-lab/tests/verify-hudi-layout.sh 1
```

注意：`sql/`、`tests/`、Hadoop XML 都是 bind mount，修改后无需重建镜像；
只有 `spark/spark-defaults.conf`、`spark/log4j2.properties` 在镜像内，需要重新 build。

## 12. 已知限制

- 单 NameNode / 单 DataNode，复制因子 1，无高可用；
- 关闭 HDFS 权限检查，仅适用于学习环境；
- 内嵌 Derby 元数据，同一时刻只能有一个 Spark SQL 会话；
- 镜像只按 `linux/amd64` 构建，未做 ARM64 适配；
- Linux 脚本未在真实 Linux 主机上完成部署验证（开发机为 Windows）。
