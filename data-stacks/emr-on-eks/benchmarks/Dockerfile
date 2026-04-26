# EMR on EKS TPC-DS Benchmark Image — Multi-arch (linux/amd64 + linux/arm64)
#
# Source image: provide the EMR benchmark base image via `EMR_BASE_IMAGE`
# Based on:     https://github.com/aws-samples/emr-on-eks-benchmark
#
# The benchmark base image should be supplied at build time via `EMR_BASE_IMAGE`.
#
# To rebuild from scratch (if source image is updated), the multi-stage build below
# compiles tpcds-kit and the benchmark JAR. byacc is required in AL2023 for yacc support.
#
# Three build stages:
#   1. tpc-toolkit  — compile tpcds-kit C tools for the TARGET arch (dsdgen/dsqgen binaries)
#   2. sbt-build    — compile Scala benchmark JAR on the BUILD host (JVM = arch-independent)
#   3. final        — EMR base image + tpcds-kit tools + benchmark JAR
#
# Build & push (requires docker buildx + QEMU for cross-compilation):
#
#   EMR_BASE_IMAGE=<emr-base-image-uri>
#   REPO=<benchmark-image-uri>
#
#   # Log into registries as needed
#   docker login <registry>
#
#   # Set up QEMU for arm64 cross-compilation (one-time)
#   docker run --privileged --rm tonistiigi/binfmt --install all
#
#   # Build and push multi-arch manifest in one step
#   docker buildx build \
#       --platform linux/amd64,linux/arm64 \
#       --build-arg EMR_BASE_IMAGE=$EMR_BASE_IMAGE \
#       --tag $REPO:latest \
#       --push \
#       .
#
# SOCI: run once after push to enable lazy-loading on AL2023 nodes:
#   aws ecr put-registry-scanning-configuration \
#       --scan-type ENHANCED \
#       --rules '[{"repositoryFilters":[{"filter":"emr-eks-tpcds-benchmark","filterType":"WILDCARD"}],"scanFrequency":"SCAN_ON_PUSH"}]' \
#       --region <aws-region>

# ── Stage 1: tpcds-kit native C tools ───────────────────────────────────────
# Runs on the TARGET platform so the dsdgen/dsqgen binaries match the node arch.
# docker buildx uses QEMU to emulate arm64 when building on an x86 host.
FROM amazonlinux:2023 AS tpc-toolkit

# byacc provides /usr/bin/yacc which the tpcds-kit Makefile requires.
# In AL2023, bison alone does NOT install /usr/bin/yacc — byacc fills that gap.
RUN dnf install -y gcc make git flex bison byacc patch && \
    git clone https://github.com/databricks/tpcds-kit.git /tmp/tpcds-kit && \
    cd /tmp/tpcds-kit/tools && \
    make OS=LINUX

# ── Stage 2: Scala benchmark JAR ────────────────────────────────────────────
# JVM bytecode is architecture-independent; run this stage on the BUILD host
# (native speed) so we don't have to emulate the slow SBT compile via QEMU.
FROM --platform=$BUILDPLATFORM eclipse-temurin:11-jdk AS sbt-build

# Install SBT
ARG SBT_VERSION=1.9.9
RUN apt-get update && apt-get install -y curl git && \
    curl -fsSL "https://github.com/sbt/sbt/releases/download/v${SBT_VERSION}/sbt-${SBT_VERSION}.tgz" \
        | tar -xz -C /usr/local && \
    ln -s /usr/local/sbt/bin/sbt /usr/local/bin/sbt

# Clone the full emr-on-eks-benchmark repo (includes spark-sql-perf sub-project)
ARG BENCHMARK_REPO=https://github.com/aws-samples/emr-on-eks-benchmark.git
ARG BENCHMARK_BRANCH=main
RUN git clone --depth 1 -b ${BENCHMARK_BRANCH} ${BENCHMARK_REPO} /tmp/emr-on-eks-benchmark

WORKDIR /tmp/emr-on-eks-benchmark

# Update Spark dependency to match the selected EMR base image Spark version
# The "provided" scope means this only affects compilation — the runtime Spark
# is supplied by the EMR base image.
RUN sed -i \
      's|"org.apache.spark" %% "spark-core" % "[^"]*"|"org.apache.spark" %% "spark-core" % "3.5.1"|g; \
       s|"org.apache.spark" %% "spark-sql"  % "[^"]*"|"org.apache.spark" %% "spark-sql"  % "3.5.1"|g; \
       s|"org.apache.spark" %% "spark-sql"% "[^"]*"|"org.apache.spark" %% "spark-sql" % "3.5.1"|g' \
      benchmark/build.sbt

# Build spark-sql-perf library first (required by benchmark)
RUN cd spark-sql-perf && sbt +package

# Build the benchmark assembly JAR
RUN mkdir -p benchmark/libs && \
    cp spark-sql-perf/target/scala-2.12/*.jar benchmark/libs/ && \
    cd benchmark && sbt assembly

# ── Stage 3: Final EMR image ─────────────────────────────────────────────────
ARG EMR_BASE_IMAGE
FROM ${EMR_BASE_IMAGE}

USER root

# tpcds-kit tools (arch-specific C binaries: dsdgen, dsqgen, etc.)
COPY --from=tpc-toolkit /tmp/tpcds-kit/tools /opt/tpcds-kit/tools

# Benchmark JAR (JVM bytecode — same JAR works on amd64 and arm64)
COPY --from=sbt-build \
     /tmp/emr-on-eks-benchmark/benchmark/target/scala-2.12/eks-spark-benchmark-assembly-1.0.jar \
     ${SPARK_HOME}/examples/jars/eks-spark-benchmark-assembly-1.0.jar

RUN chmod 755 /opt/tpcds-kit/tools/* && \
    chown -R hadoop:hadoop /opt/tpcds-kit && \
    chown hadoop:hadoop ${SPARK_HOME}/examples/jars/eks-spark-benchmark-assembly-1.0.jar

# Pre-create Spark local dir inside the image as a fallback
# (the node userData and emptyDir mount are the primary mechanism)
RUN mkdir -p /tmp/spark-local && chmod 1777 /tmp/spark-local

USER hadoop:hadoop
