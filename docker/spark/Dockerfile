#
# Hudi Lab Portable —— Spark 3.3.1 + Hudi 0.15.0
#
# 基础镜像固定为 apache/spark:3.3.1（与已验证环境一致）。
# Hudi bundle 在构建期从 Maven Central 下载并校验 SHA256，
# 不依赖宿主机上已有的 JAR，也不把 JAR 提交进 Git。
#
# 版本锁定：
#   Spark   3.3.1  (Scala 2.12, Java 11)
#   Hudi    0.15.0 (hudi-spark3.3-bundle_2.12)
# =============================================================

FROM alpine:3.20 AS hudi-bundle

ARG HUDI_VERSION=0.15.0
ARG HUDI_BUNDLE=hudi-spark3.3-bundle_2.12
# 官方 Maven Central 产物的 SHA256（hudi-spark3.3-bundle_2.12-0.15.0.jar）
ARG HUDI_SHA256=7ade6ae19a634f94e1633781630d991b2278fe19271913c5a4a7a652b9d5fda7

RUN apk add --no-cache curl ca-certificates \
 && mkdir -p /opt/hudi \
 && JAR="${HUDI_BUNDLE}-${HUDI_VERSION}.jar" \
 && curl -fsSL --retry 5 --retry-delay 3 \
      -o "/opt/hudi/${JAR}" \
      "https://repo1.maven.org/maven2/org/apache/hudi/${HUDI_BUNDLE}/${HUDI_VERSION}/${JAR}" \
 && echo "${HUDI_SHA256}  /opt/hudi/${JAR}" | sha256sum -c - \
 && ls -l "/opt/hudi/${JAR}"


FROM apache/spark:3.3.1

LABEL org.opencontainers.image.title="hudi-lab-spark" \
      org.opencontainers.image.description="Apache Spark 3.3.1 + Apache Hudi 0.15.0 for Hudi Lab Portable" \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.licenses="Apache-2.0"

USER root

COPY --from=hudi-bundle /opt/hudi/hudi-spark3.3-bundle_2.12-0.15.0.jar /opt/hudi/
COPY spark/spark-defaults.conf /opt/spark/conf/spark-defaults.conf
COPY spark/log4j2.properties   /opt/spark/conf/log4j2.properties

# 命名卷挂载点预先创建（属主保持 root，与已验证环境一致）
RUN mkdir -p /workspace/warehouse /workspace/metastore /workspace/sql

WORKDIR /workspace

# 常驻，通过 docker compose exec 执行 spark-sql / spark-submit
CMD ["tail", "-f", "/dev/null"]
