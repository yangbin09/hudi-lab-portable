# Hudi Lab Portable

可移植的 **Apache Hadoop HDFS 3.3.6 + Apache Spark 3.3.1 + Apache Hudi 0.15.0** 单机实验环境。
Windows / Linux 使用同一套 `compose.yaml`，一条命令完成部署、健康检查和真实功能测试。

> 这是一个**单机学习环境**：单 NameNode、单 DataNode、复制因子 1、关闭 HDFS 权限检查。
> 不要用于生产环境。

---

## 快速部署

### Windows

准备：Docker Desktop（Linux containers 模式）、Git、PowerShell 5.1+。

```powershell
git clone https://github.com/yangbin09/hudi-lab-portable.git
cd hudi-lab-portable
.\scripts\windows\bootstrap.ps1
```

### Linux

准备：Docker Engine、Docker Compose Plugin、Git、Bash。
宿主机**不需要**安装 Java、Hadoop、Spark、Hudi。

```bash
git clone https://github.com/yangbin09/hudi-lab-portable.git
cd hudi-lab-portable
chmod +x scripts/linux/*.sh
./scripts/linux/bootstrap.sh
```

部署完成后：

```powershell
.\scripts\windows\status.ps1     # Windows
```
```bash
./scripts/linux/status.sh        # Linux
```

---

## 部署后得到什么

| 组件 | 版本 | 说明 |
|---|---|---|
| Hadoop HDFS | 3.3.6 | NameNode + DataNode，`hdfs://namenode:9000` |
| Apache Spark | 3.3.1 | local[*]，Java 11，Scala 2.12 |
| Apache Hudi | 0.15.0 | `hudi-spark3.3-bundle_2.12-0.15.0.jar` |
| 容器数量 | 3 | namenode / datanode / spark |

宿主机端口（**只绑定 127.0.0.1**，可在 `.env` 修改）：

| 服务 | 容器端口 | 宿主机端口 |
|---|---|---|
| NameNode RPC | 9000 | 19000 |
| NameNode Web UI | 9870 | 19870 |
| DataNode Web UI | 9864 | 19864 |

> 容器内部始终使用 `hdfs://namenode:9000`，宿主机端口只用于本机调试和浏览器访问。

NameNode UI：<http://127.0.0.1:19870>

---

## 日常命令

| 操作 | Windows | Linux |
|---|---|---|
| 首次部署 / 复用 | `.\scripts\windows\bootstrap.ps1` | `./scripts/linux/bootstrap.sh` |
| 启动 | `.\scripts\windows\up.ps1` | `./scripts/linux/up.sh` |
| 停止（保留数据） | `.\scripts\windows\down.ps1` | `./scripts/linux/down.sh` |
| 状态 | `.\scripts\windows\status.ps1` | `./scripts/linux/status.sh` |
| 只读诊断 | `.\scripts\windows\doctor.ps1` | `./scripts/linux/doctor.sh` |
| 删除本环境 | `.\scripts\windows\destroy.ps1` | `./scripts/linux/destroy.sh` |
| Spark SQL | `.\scripts\windows\spark-sql.ps1` | `./scripts/linux/spark-sql.sh` |
| HDFS 命令 | `.\scripts\windows\hdfs.ps1 dfs -ls /` | `./scripts/linux/hdfs.sh dfs -ls /` |

`bootstrap` 是幂等的：重复执行只会检查并复用环境，**不会重新格式化 NameNode，也不会删除数据**。

### 常用示例

```powershell
# HDFS
.\scripts\windows\hdfs.ps1 dfs -ls /
.\scripts\windows\hdfs.ps1 dfsadmin -report
.\scripts\windows\hdfs.ps1 fsck / -files -blocks

# 把文件放到 transfer/ 后上传（Windows 路径会自动映射）
.\scripts\windows\hdfs.ps1 dfs -put .\transfer\test.csv /datasets/

# Spark SQL
.\scripts\windows\spark-sql.ps1
.\scripts\windows\spark-sql.ps1 -f /workspace/sql/cow-test.sql
```

```bash
# Linux 等价命令
./scripts/linux/hdfs.sh dfs -ls /
./scripts/linux/hdfs.sh dfs -put ./transfer/test.csv /datasets/
./scripts/linux/spark-sql.sh -e "SHOW DATABASES"
```

---

## 数据持久化

使用 4 个 Docker Named Volume，全部属于 Compose 项目 `hudi-lab-portable`：

| 卷 | 挂载点 | 内容 |
|---|---|---|
| `hudi-lab-portable_namenode-data` | `/data` | NameNode 元数据 |
| `hudi-lab-portable_datanode-data` | `/data` | HDFS 数据块 |
| `hudi-lab-portable_spark-warehouse` | `/workspace/warehouse` | Spark warehouse |
| `hudi-lab-portable_spark-metastore` | `/workspace/metastore` | Derby 元数据 |

- `down` 只删除容器和网络，卷保留；
- 容器重建、Docker 重启后数据仍在；
- 只有 `destroy` 会在输入完整确认字符串后删除这些卷；
- 不使用 `docker volume prune` / `docker system prune`。

---

## 自动验收

`bootstrap` 结束前会真实执行：

| 测试 | 内容 |
|---|---|
| HDFS | mkdir / put / cat / ls / `dfsadmin -report` / `fsck`，要求 HEALTHY、Live DataNodes=1、Safe Mode OFF |
| Spark | Spark SQL 写 HDFS Parquet 再读回，校验行数与内容 |
| Hudi COW | 建表 / INSERT / UPDATE / DELETE / SELECT / SHOW PARTITIONS / Timeline / Parquet 文件 |
| Hudi MOR | 建表 / INSERT / UPDATE / DELETE / 快照读 / 读优化读 / deltacommit / `.log` 文件 |

测试数据使用独立 run id（`/tmp/hudi-lab-portable-test/<run-id>`）和独立数据库
`hudi_lab_portable_test`，结束后只清理本次测试资源。

可选：`bootstrap -PersistenceTest`（Linux 为 `--persistence-test`）会额外执行
`docker compose down` + `up`，验证容器重建后 HDFS 文件与 Hudi 表仍然存在。

---

## 镜像

已发布到 GHCR（公共镜像，匿名可拉取）：

| 项目 | 值 |
|---|---|
| 默认镜像（`.env.example`） | `ghcr.io/yangbin09/hudi-lab-spark:0.1.1` |
| Git SHA 标签 | `sha-0281409bdd4e` |
| Digest | `sha256:21817c68f09032a3078d742761e6b4f4beace4e9f1ca1cf388ad0cecb8c166ad` |

`bootstrap` 在本地没有该镜像时会自动执行 `docker compose pull spark`。
镜像为公开，无需 `docker login`。

需要完全本地构建时，在 `.env` 中设置：

```dotenv
SPARK_IMAGE=hudi-lab-portable-spark:0.1.0
```

然后执行：

```bash
docker compose build spark
```

镜像构建时从 Maven Central 下载固定版本 Hudi JAR 并校验 SHA256，
不依赖宿主机已有 JAR，也不把 JAR 提交进 Git。

发布由 `.github/workflows/release.yml` 在 `v*` 标签触发，发布记录见
[GitHub Actions](https://github.com/yangbin09/hudi-lab-portable/actions)。

---

## 目录结构

```
hudi-lab-portable/
├── .github/workflows/      CI 与 GHCR 发布
├── docker/spark/           Spark + Hudi Dockerfile
├── hadoop/                 NameNode / DataNode XML 与格式化守卫
├── spark/                  spark-defaults.conf、日志配置、客户端 HDFS 配置
├── sql/                    COW / MOR 测试 SQL
├── tests/                  容器内冒烟测试脚本
├── scripts/windows/        Windows 管理脚本
├── scripts/linux/          Linux 管理脚本
├── docs/                   Windows / Linux / 开发文档
├── transfer/               宿主机与容器共享文件中转目录
├── compose.yaml
└── .env.example
```

---

## 已知兼容处理

沿用已验证环境的处理方式，不升级 Hadoop 客户端依赖：

```properties
hoodie.metadata.enable=false
hoodie.datasource.hive_sync.enable=false
```

原因：Spark 3.3.1 自带 `hadoop-client 3.3.2`，Hudi bundle 通过 HBase 读取 Metadata Table 时
会触发 `NoSuchMethodError: HdfsDataInputStream.getReadStatistics`。
MOR 测试同时关闭 inline compaction，以便观察真实的 Base File + Log File。

详细说明见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

---

## 更多文档

- [Windows 使用说明](docs/WINDOWS.md)
- [Linux 使用说明](docs/LINUX.md)
- [开发与设计说明](docs/DEVELOPMENT.md)
- [验收报告](docs/ACCEPTANCE.md)

## 许可

Apache-2.0
