# Linux 使用说明

适用于安装有 Docker Engine + Docker Compose Plugin 的常见 Linux 发行版（x86_64）。

## 1. 前置条件

| 项目 | 要求 |
|---|---|
| Docker Engine | 已安装并运行 |
| Docker Compose Plugin | `docker compose` 可用（v2+） |
| Git | 任意版本 |
| Bash | 4.0+ |
| 权限 | 当前用户可执行 docker（加入 `docker` 组，或用 sudo） |
| 内存 | ≥ 4 GB（推荐 8 GB 以上） |
| 磁盘 | 建议 ≥ 10 GB 可用空间 |

宿主机**不需要**安装 Java、Hadoop、Spark、Hudi。
脚本不会修改防火墙，也不会把端口暴露到公网。

## 2. 首次部署

```bash
git clone https://github.com/yangbin09/hudi-lab-portable.git
cd hudi-lab-portable
chmod +x scripts/linux/*.sh
./scripts/linux/bootstrap.sh
```

成功时最后输出：

```
Deployment:   SUCCESS
```

可选参数：

```bash
./scripts/linux/bootstrap.sh --persistence-test   # 额外验证容器重建后数据仍在
./scripts/linux/bootstrap.sh --skip-tests         # 只部署，不跑冒烟测试
./scripts/linux/bootstrap.sh --timeout 600        # 自定义等待超时（秒）
```

`bootstrap` 是幂等的：重复执行会复用已有数据卷，不会重新格式化 NameNode。

## 3. 日常命令

```bash
./scripts/linux/status.sh      # 状态
./scripts/linux/doctor.sh      # 只读诊断
./scripts/linux/up.sh          # 启动
./scripts/linux/down.sh        # 停止（保留数据）
./scripts/linux/destroy.sh     # 彻底删除本项目环境
```

## 4. 进入 Spark SQL

```bash
./scripts/linux/spark-sql.sh
./scripts/linux/spark-sql.sh -f /workspace/sql/cow-test.sql
./scripts/linux/spark-sql.sh -e "SHOW DATABASES"
```

同一时刻只允许一个 `spark-sql` / `spark-shell` 进程（内嵌 Derby 元数据锁）。

## 5. 操作 HDFS

```bash
./scripts/linux/hdfs.sh dfs -ls /
./scripts/linux/hdfs.sh dfs -mkdir -p /warehouse
./scripts/linux/hdfs.sh dfsadmin -report
./scripts/linux/hdfs.sh fsck / -files -blocks
```

文件交换目录为仓库下的 `transfer/`（容器内 `/transfer`）：

```bash
./scripts/linux/hdfs.sh dfs -put ./transfer/test.csv /datasets/
./scripts/linux/hdfs.sh dfs -cat /datasets/test.csv
```

## 6. 访问 Web UI

| 页面 | 地址 |
|---|---|
| NameNode | <http://127.0.0.1:19870> |
| DataNode | <http://127.0.0.1:19864> |

端口只绑定 `127.0.0.1`。如需从其它机器访问，请自行通过 SSH 隧道，
不要直接把端口改成 `0.0.0.0`。

## 7. 修改端口或镜像

编辑 `.env`：

```dotenv
NN_RPC_PORT=19000
NN_WEB_PORT=19870
DN_WEB_PORT=19864
SPARK_IMAGE=ghcr.io/yangbin09/hudi-lab-spark:0.1.1
```

`SPARK_IMAGE` 默认指向公共 GHCR 镜像，匿名可拉取，无需登录。
私有镜像才需要：

```bash
echo "<token>" | docker login ghcr.io -u <github-user> --password-stdin
```

```bash
./scripts/linux/down.sh
./scripts/linux/up.sh
```

## 8. 数据位置

4 个命名卷：

- `hudi-lab-portable_namenode-data`
- `hudi-lab-portable_datanode-data`
- `hudi-lab-portable_spark-warehouse`
- `hudi-lab-portable_spark-metastore`

`down` 保留卷；`destroy` 在输入 `DELETE HUDI LAB PORTABLE` 后才删除。
脚本从不执行 `docker volume prune` 或 `docker system prune`。

## 9. 常见问题

**`permission denied while trying to connect to the Docker daemon socket`**
把用户加入 docker 组后重新登录：

```bash
sudo usermod -aG docker "$USER"
```

**没有 `docker compose` 子命令**
安装 Docker Compose Plugin（例如 Debian/Ubuntu 的 `docker-compose-plugin` 包）。
本项目要求 `docker compose`，不使用旧的 `docker-compose`。

**端口被占用**
修改 `.env` 中三个端口，或释放占用端口的进程。脚本不会停止其它容器。

**SELinux 阻止挂载**
在 Fedora / RHEL 上如果容器报权限错误，可为项目目录添加挂载标签：

```bash
sudo chcon -Rt svirt_sandbox_file_t "$PWD"
```

**内存不足**
Docker 可用内存低于 4 GB 时 `bootstrap` 会直接报错退出。

## 10. 关于跨架构

镜像按 `linux/amd64` 构建。在 ARM64 主机上 Docker 可能启用模拟运行，
本项目**不支持也不自动启用**模拟；如果不兼容，部署会明确失败，而不是静默降级。

## 11. 验证状态说明

Linux 脚本已完成静态检查（`bash -n`）与逻辑对齐，但当前开发机为 Windows，
**未在真实 Linux 主机上执行过完整部署**。首次在 Linux 使用时如遇问题，
请保留 `bootstrap` 输出与 `docker compose logs` 以便定位。
