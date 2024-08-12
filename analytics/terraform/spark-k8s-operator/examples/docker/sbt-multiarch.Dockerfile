# to build the benchmarks we need an `sbt` image, there are some on Dockerhub https://github.com/mozilla/docker-sbt
# but those images aren't cross platform arm64/amd64 so i ran into build issues for the benchmark image.
# This is the dockerfile used to build the intermediate containers used in the benchmark image
#
# docker buildx build --platform linux/amd64,linux/arm64 -f sbt-multiarch.Dockerfile -t 111111111111.dkr.ecr.region.amazonaws.com/sbt-multiarch:1.6.2-openjdk11.0.13 --push --no-cache --progress=plain . 2>&1 | tee sbt-multiarch1.6.2.log

# This Dockerfile has two required ARGs to determine which base image to use for the JDK and which sbt version to install.
ARG OPENJDK_TAG=11.0.13
FROM openjdk:${OPENJDK_TAG}

ARG SBT_VERSION=1.6.2

# prevent this error: java.lang.IllegalStateException: cannot run sbt from root directory without -Dsbt.rootdir=true; see sbt/sbt#1458
WORKDIR /app
# Install sbt
RUN \
  mkdir /working/ && \
  cd /working/ && \
  curl -L -o sbt-$SBT_VERSION.deb https://repo.scala-sbt.org/scalasbt/debian/sbt-$SBT_VERSION.deb && \
  dpkg -i sbt-$SBT_VERSION.deb && \
  rm sbt-$SBT_VERSION.deb && \
  apt-get update && \
  apt-get install -y sbt && \
  cd && \
  rm -r /working/ && \
  sbt sbtVersion
