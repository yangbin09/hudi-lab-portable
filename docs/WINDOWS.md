# Windows 使用说明

适用于 Windows 10/11 + Docker Desktop（WSL2 后端，Linux containers 模式）。

## 1. 前置条件

| 项目 | 要求 |
|---|---|
| Docker Desktop | 已安装并启动，使用 **Linux containers** |
| Docker Compose | v2+（Docker Desktop 自带） |
| Git | 任意版本 |
| PowerShell | 5.1 或更高 |
| Docker 内存 | ≥ 4 GB（推荐 8 GB 以上） |
| 磁盘 | 建议 ≥ 10 GB 可用空间 |

宿主机**不需要**安装 Java、Hadoop、Spark、Hudi。

## 2. 首次部署

```powershell
git clone https://github.com/yangbin09/hudi-lab-portable.git
cd hudi-lab-portable
.\scripts\windows\bootstrap.ps1
```

如果提示脚本被禁止执行，可临时使用：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\windows\bootstrap.ps1
```

`bootstrap` 会自动：

1. 检查 Docker Engine / Compose / Linux 模式 / 内存 / 磁盘；
2. 从 `.env.example` 创建 `.env`；
3. 首次部署时检查 19000 / 19870 / 19864 是否被占用；
4. 镜像缺失时构建 `hudi-lab-portable-spark:0.1.0`；
5. 依次启动 NameNode → DataNode → Spark，并等待健康检查；
6. 等待 DataNode 注册、Safe Mode 关闭；
7. 执行 HDFS / Spark / Hudi COW / Hudi MOR 冒烟测试；
8. 输出最终状态。

部署成功的标志是最后一行：

```
Deployment:   SUCCESS
```

## 3. 日常命令

```powershell
.\scripts\windows\status.ps1      # 状态
.\scripts\windows\doctor.ps1      # 只读诊断
.\scripts\windows\up.ps1          # 启动
.\scripts\windows\down.ps1        # 停止（保留数据）
.\scripts\windows\destroy.ps1     # 彻底删除本项目环境
```

`bootstrap` 可以重复执行：已存在的数据卷和 NameNode 元数据会被复用，
格式化守卫脚本检测到 `current/VERSION` 后会跳过格式化。

## 4. 进入 Spark SQL

```powershell
.\scripts\windows\spark-sql.ps1
```

执行 SQL 文件或单条语句：

```powershell
.\scripts\windows\spark-sql.ps1 -f /workspace/sql/cow-test.sql
.\scripts\windows\spark-sql.ps1 -e "SHOW DATABASES"
```

> Spark SQL 使用内嵌 Derby 元数据库，**同一时刻只允许一个** `spark-sql` / `spark-shell` 进程。
> 并发执行会报 Derby 锁冲突。

## 5. 操作 HDFS

```powershell
.\scripts\windows\hdfs.ps1 dfs -ls /
.\scripts\windows\hdfs.ps1 dfs -mkdir -p /warehouse
.\scripts\windows\hdfs.ps1 dfsadmin -report
.\scripts\windows\hdfs.ps1 fsck / -files -blocks
```

上传/下载文件：把文件放入仓库的 `transfer\` 目录（容器内为 `/transfer`），
Windows 绝对路径会被自动映射：

```powershell
.\scripts\windows\hdfs.ps1 dfs -put .\transfer\test.csv /datasets/
.\scripts\windows\hdfs.ps1 dfs -cat /datasets/test.csv
```

如果传入 `transfer\` 之外的 Windows 路径，脚本会明确报错并以退出码 2 退出。

## 6. 访问 Web UI

| 页面 | 地址 |
|---|---|
| NameNode | <http://127.0.0.1:19870> |
| DataNode | <http://127.0.0.1:19864> |
| Spark UI | 已关闭（`spark.ui.enabled=false`） |

端口只绑定 `127.0.0.1`，不会对局域网或公网开放。

## 7. 修改端口或镜像

编辑 `.env`：

```dotenv
NN_RPC_PORT=19000
NN_WEB_PORT=19870
DN_WEB_PORT=19864
SPARK_IMAGE=hudi-lab-portable-spark:0.1.0
```

修改端口后执行：

```powershell
.\scripts\windows\down.ps1
.\scripts\windows\up.ps1
```

## 8. 使用 GHCR 镜像

```dotenv
SPARK_IMAGE=ghcr.io/<github-owner>/hudi-lab-spark:0.1.0
```

```powershell
docker login ghcr.io    # 私有镜像才需要
.\scripts\windows\up.ps1
```

`bootstrap` / `up` 发现本地没有该镜像时会执行 `docker compose pull spark`。
拉取失败且本地也没有镜像时，会明确报错，不会静默回退。

## 9. 数据位置

| 内容 | 位置 |
|---|---|
| HDFS NameNode 元数据 | 卷 `hudi-lab-portable_namenode-data` |
| HDFS 数据块 | 卷 `hudi-lab-portable_datanode-data` |
| Spark warehouse | 卷 `hudi-lab-portable_spark-warehouse` |
| Derby 元数据 | 卷 `hudi-lab-portable_spark-metastore` |
| 卷的物理位置 | Docker Desktop 的虚拟磁盘（由 Docker 配置决定） |

`down` 不会删除卷；只有 `destroy` 在完整确认后才删除。

## 10. 常见问题

**找不到 docker 命令**
新开终端 PATH 未刷新。脚本会自动探测
`%LOCALAPPDATA%\Programs\DockerDesktop\resources\bin` 与
`%ProgramFiles%\Docker\Docker\resources\bin`；也可以重启终端。

**提示端口被占用**
脚本不会停止其它容器。修改 `.env` 中的三个端口，或自行释放端口。
注意不要与旧 `hudi-lab` 环境使用的 9000 / 9870 / 9864 冲突。

**Docker 不是 Linux Containers 模式**
在 Docker Desktop 托盘菜单中切换到 "Linux containers"。

**Spark 写入 HDFS 报 `HdfsDataInputStream.getReadStatistics`**
这是已知兼容问题。本项目的 Hudi 测试 SQL 已关闭 metadata table 与 Hive Sync，
不要自行打开 `hoodie.metadata.enable`。

**Derby 锁冲突**
同一时间只运行一个 `spark-sql` / `spark-shell`。先退出其它会话再重试。

**想彻底重来**
```powershell
.\scripts\windows\destroy.ps1
.\scripts\windows\bootstrap.ps1
```
`destroy` 需要输入完整字符串 `DELETE HUDI LAB PORTABLE`。
