---
sidebar_position: 2
sidebar_label: Cloud Native PostGres Operator
---

# Run CloudNativePG operator to manage your Postgres DataBase on EKS

## Introduction

CloudNativePG is an open source operator designed to manage PostgreSQL workloads on any supported Kubernetes cluster. It defines a new Kubernetes resource called Cluster representing a PostgreSQL cluster made up of a single primary and an optional number of replicas that co-exist in a chosen Kubernetes namespace for High Availability and offloading of read-only queries.

CloudNativePG was originally built by EDB, then released open source under Apache License 2.0 and submitted for CNCF Sandbox in April 2022. The source code repository is in Github.
