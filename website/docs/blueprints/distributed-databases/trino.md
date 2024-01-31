---
sidebar_position: 3
sidebar_label: Trino on EKS
---

# Deploying Trino on EKS

## Introduction

**Trino** is an [open source query engine](https://trino.io/) designed to run distributed SQL query engine for data analytics.

It defines a new Kubernetes resource called `Cluster` representing a Trino cluster consisting of a coordinator and many workers (for high availability) as k8s pods. The coordinator and the workers collaborate to access connected data sources, with schemas and references stored in a catalog. To access the data sources, you can use one of the many [connectors](https://trino.io/docs/current/connector.html) provided by Trino to adapt Trino. Examples include as Hive, Iceberg, and Kafka.

More details about the project will be found on this [link](https://trino.io)

## Blueprint Solution

This blueprint will deploy Trino on an EKS cluster with nodes provisioned using Karpenter. To optimize on cost and performance, Karpenter will provision on-demand nodes for the coordinator and spot instances for the workers. Trino is deployed using the official Helm chart, with custom values provided for users to leverage either Hive or Iceberg as the connector. The examples will use Glue or Iceberg tables on AWS as the backend data source, using S3 as the storage.

## Deploying the Solution

Let's go through the deployment steps.

### Prerequisites

Ensure that you have installed the following tools on your machine.

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)
4. [trino cli client](https://trino.io/docs/current/client/cli.html)

### Deploy the EKS Cluster with Trino

First, clone the repository

```bash
git clone https://github.com/awslabs/data-on-eks.git
```

Navigate into `distributed-databases/trino` and run `install.sh` script. By default the script deploys EKS cluster to `us-west-2` region. Update `variables.tf` to change the region. This is also the time to update any other input variables or make any other changes to the terraform template.

```bash
cd data-on-eks/distributed-databases/trino

./install.sh
```

### Verify Deployment

Verify the Amazon EKS Cluster

```bash
aws eks describe-cluster --name trino-on-eks
```

Update local kubeconfig so we can access kubernetes cluster (you can also get this command from the terraform output `configure_kubectl`)

```bash
aws eks update-kubeconfig --name trino-on-eks --region us-west-2
```

First, lets verify that we have worker nodes running in the cluster.

```bash
kubectl get nodes
NAME                                        STATUS   ROLES    AGE     VERSION
ip-10-1-10-192.us-west-2.compute.internal   Ready    <none>   4d17h   v1.27.6-eks-a5df82a
ip-10-1-10-249.us-west-2.compute.internal   Ready    <none>   4d17h   v1.27.6-eks-a5df82a
ip-10-1-11-38.us-west-2.compute.internal    Ready    <none>   4d17h   v1.27.6-eks-a5df82a
ip-10-1-12-195.us-west-2.compute.internal   Ready    <none>   4d17h   v1.27.6-eks-a5df82a
```

Next, lets verify all the pods are running.

```bash
kubectl get pods --namespace=trino
NAME                                 READY   STATUS    RESTARTS      AGE
trino-coordinator-7c644cd9f5-j65ch   1/1     Running   0             24d
trino-worker-7f8565698-ctjr4         1/1     Running   0             13d
trino-worker-7f8565698-hhcwb         1/1     Running   0             24d
trino-worker-7f8565698-q4bvd         1/1     Running   1             24d
```

## Using Trino for database querying executions

### Example #1: Using the Hive Connector

In this example, we will set up a Hive metastore using AWS Glue, with the source data stored in S3, and crawler that will infer schema from it to build a Glue table.

Using Trino on EKS with the Glue connector, we will use Trino CLI to run sample SQL queries to retrieve data.

#### Setup

Run the hive script from the `examples` directory to set up the blueprint S3 bucket with the 2022 NYC Taxi dataset (in Parquet), and build Glue metastore:

```bash
cd examples/
./hive.sh
```

You will see some outputs to show progress, and if successful, will see the name of the Glue table that will store the metadata as `hive`.

#### Running the queries
You should have the Trino CLI installed as part of the prerequisite. The blueprint has the Hive Connector configured with the bucket we set up in the previous section, so you should be able to query the data source without additional settings.

First, port-forward your trino coordinator pod to access it locally:
```
kubectl port-forward
```

In another terminal tab, while the port-forward is running, run the following command to access the coordinator:
```bash
./trino http://127.0.0.1:8080 --user admin
```

Once successful, you will be able to get a prompt to execute commands. You can use `help` command to see a list of supported commands.

For example:

To show a list of catalogs - `SHOW CATALOG`:

```bash
Catalog
---------
 hive
 system
 tpcds
 tpch
(4 rows)

Query 20231103_221729_00028_6dv3m, FINISHED, 1 node
Splits: 1 total, 1 done (100.00%)
0.21 [0 rows, 0B] [0 rows/s, 0B/s]
```

To show the Hive catalog schemas - `SHOW SCHEMAS FROM hive`:

```bash
  Schema
--------------------
 information_schema
 taxi_hive_database
(2 rows)
```

To show our Taxi table -
```
USE hive.taxi_hive_database
SHOW TABLES;
```

```
Table
-------
hive
(1 row)
```

Finally, to run a simple query to list items - `SELECT * FROM hive LIMIT 5`

```
vendorid |  tpep_pickup_datetime   |  tpep_dropoff_datetime  | passenger_count | trip_distance | ratecodeid | store_and_fwd_flag | pulocationid | dolocation>
----------+-------------------------+-------------------------+-----------------+---------------+------------+--------------------+--------------+----------->
        1 | 2022-09-01 00:28:12.000 | 2022-09-01 00:36:22.000 |             1.0 |           2.1 |        1.0 | N                  |          100 |          2>
        1 | 2022-11-01 00:24:49.000 | 2022-11-01 00:31:04.000 |             2.0 |           1.0 |        1.0 | N                  |          158 |          1>
        1 | 2022-11-01 00:37:32.000 | 2022-11-01 00:42:23.000 |             2.0 |           0.8 |        1.0 | N                  |          249 |          1>
        2 | 2022-09-01 00:02:24.000 | 2022-09-01 00:09:39.000 |             1.0 |          1.32 |        1.0 | N                  |          238 |          1>
        2 | 2022-09-01 00:47:25.000 | 2022-09-01 00:56:09.000 |             1.0 |          2.94 |        1.0 | N                  |
```

#### Clean Up

### Example #2: Using the Iceberg Connector

In this example, we will set up using Apache Iceberg with AWS Glue as the catalog type, and will store the data in Amazon S3 with PARQUET format. 

Using Trino on EKS with the Iceberg connector, we will use Trino CLI to create the above resources and run sample SQL queries to insert and retrieve data.

#### Setup

#### Running the queries

## Conclusion

Trino provides a tool for efficiently querying vast amounts of data from your data sources.
In this example, we share a blueprint that deploy Trino on Amazon EKS, with addons necessary to build a complete EKS cluster (i.e. Karpenter for autoscaling, monitoring with Prometheus/Grafana stack). Among many features, we highlighted a couple of examples on creating an Iceberg or Hive data store using Amazon S3 as storage, and using simple queries for results. 