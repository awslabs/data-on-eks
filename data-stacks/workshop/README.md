# Holistic Cat Cafe: Real-Time Data Platform Workshop

Build a complete streaming data platform using the story of managing a modern cat cafe. This hands-on workshop covers the full data engineering stack—from real-time event processing to historical analytics—all deployed on Kubernetes.

## What You'll Build

A production-ready data platform that:
- Ingests live events from cafe operations (cat interactions, wellness monitoring, visitor activity)
- Processes data streams in real-time to generate alerts and insights
- Stores all data in a modern lakehouse architecture for historical analysis
- Provides live dashboards and business intelligence reports

## What You'll Learn

* **Event Streaming:** Apache Kafka as the backbone for real-time data flows
* **Stream Processing:** Apache Flink for stateless and stateful real-time analytics
* **Data Lakehouse:** Apache Iceberg on S3 for durable, queryable data storage
* **Batch Processing:** Apache Spark for large-scale data transformations
* **Cloud-Native Deployment:** Kubernetes operators for managing data infrastructure
* **Full-Stack Integration:** Connecting data pipelines to live web applications

## Prerequisites

- `kubectl` configured for your EKS cluster
- `uv` Python package manager installed
- Basic familiarity with Kubernetes concepts


## Architecture Overview

The platform follows a modern lakehouse architecture with both streaming and batch processing capabilities:

```
                                     +-----------------+
                                     |   PostgreSQL    |  (Source: Cat & Visitor Profiles)
                                     |      (DB)       |
                                     +-----------------+
                                         |         |
                              (Profile Lookups)|         | (Batch Dimension Ingestion)
                                         v         v
      +---------------------+        +-----------------+        +----------------+
      | Real-Time Producer  |------->|      Kafka      |        |   Batch Jobs   |
      | (event_producer.py) |        | (Event Broker)  |        |    (Spark)     |
      +---------------------+        +-----------------+        +----------------+
      (Generates: interactions,       (Topics: raw_events,         |         ^
       wellness, checkins)            alerts)                      |         |
                 |                            | (Alerts)           | (Analytics & Aggregates)
                 | (Raw Events)               |                    v         |
                 v                            v             +-----------------+
      +---------------------+        +-----------------+    |   Iceberg Lake  |
      |   Streaming Jobs    |------->|   Alert UI      |    |      (S3)       |
      |     (Flink)         |        |   (WebSocket)   |    +-----------------+
      +---------------------+        +-----------------+         ^        |
      (Raw Ingestion, Health         (Consumes alerts            |        |
       monitoring, adoption detection)   from Kafka)             |        v
                 |                                              +---------------+
                 '----------------------------------------------| BI Dashboard  |
                           (Writes raw events to Lake)          |  (Superset)   |
                                                                +---------------+
```

## Workshop Modules

## Module 1: Data Generation & Kafka Ingestion

**Goal:** Set up the cafe's operational database and start generating live event streams to Kafka.

### Step 1: Deploy PostgreSQL Database

Deploy the cafe's operational database containing cat and visitor profiles:

```bash
export WORKSHOPDIR=$(git rev-parse --show-toplevel)/data-stacks/workshop

kubectl apply -f $WORKSHOPDIR/manifests/postgresql.yaml
```

Wait for the pod to be ready:
```bash
kubectl wait --for=condition=ready pod/postgresql-0 -n workshop --timeout=300s
```






### Step 2: Generate Sample Data

Create realistic cat and visitor data in the database:

```bash
# Port-forward to PostgreSQL
kubectl port-forward postgresql-0 5432:5432 -n workshop &

# Generate sample data
cd $WORKSHOPDIR/src/data-flow
uv sync --frozen
uv run data-generator.py
```

**Validate:** Check that data was created:
```bash
# Connect to database
kubectl exec -it postgresql-0 -n workshop -- psql -U workshop

# Run these queries in psql:
SELECT COUNT(*) FROM cats;
SELECT COUNT(*) FROM visitors;
\q
```

You should see ~11,000 cats and ~1,000 visitors.

### Step 3: Create Kafka Resources

First, deploy the Kafka cluster provided by the Strimzi operator.

```bash
kubectl apply -f $WORKSHOPDIR/manifests/kafka-cluster.yaml
```

**Validate:** Wait for the Kafka cluster to be ready. This may take a few minutes.
```bash
kubectl wait kafka/cluster --for=condition=Ready -n kafka --timeout=300s
```

Next, set up the event streaming topics required for the workshop:

```bash
kubectl apply -f $WORKSHOPDIR/manifests/topics.yaml
```

**Validate:** Check that the `KafkaTopic` resources were created successfully in the `kafka` namespace.
```bash
kubectl get kafkatopics -n kafka
```

The following topics will be created:

| Topic Name             | Purpose                                            |
|------------------------|----------------------------------------------------|
| `cat-interactions`     | Raw events of visitors interacting with cats.      |
| `cat-wellness-iot`     | Raw IoT sensor data from cat wellness monitors.    |
| `visitor-checkins`     | Raw events generated when a visitor checks in.     |
| `cat-health-alerts`    | Alerts generated for cats showing health issues.   |
| `potential-adopters`   | Alerts for visitors showing strong adoption intent.|


### Step 4: Start Event Generation

Deploy a producer pod which will be used to generate live events:

```bash
kubectl apply -f $WORKSHOPDIR/manifests/event-producer.yaml
```

Connect to the producer pod and start the event generator script. The script will run in the background.

```bash
# Exec into the pod
kubectl exec -it event-producer -n workshop -- bash

# Inside the pod, run the following commands: 
apt update && apt install -y git curl
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc

# Clone the repo and navigate to the correct directory
git clone https://github.com/awslabs/data-on-eks.git --depth 1 --branch v2
cd data-on-eks/data-stacks/workshop/src/data-flow

# Set environment variables for the script
export DB_HOST=postgresql-0.postgresql.workshop.svc.cluster.local
export KAFKA_BROKERS=cluster-broker-0.cluster-kafka-brokers.kafka.svc:9092

# Install dependencies and run the producer in the background
uv sync --frozen
nohup uv run event-producer.py &
```

After running the `nohup` command, you can safely exit the pod shell. The process will continue running. You should see output like `Sent interaction event for cat_id=1234, visitor_id=567` printed to a `nohup.out` file.

### Step 5: Verify Event Streaming

To verify that events are flowing correctly, deploy a separate debug pod that contains the Kafka command-line tools:

```bash
kubectl apply -f $WORKSHOPDIR/manifests/kafka-debug-pod.yaml
```

Once the pod is running, use it to consume messages from the `cat-interactions` topic. The `--from-beginning` flag ensures you see all messages in the topic from the start.

```bash
kubectl exec -it kafka-debug-pod -n workshop -- \
  kafka-console-consumer \
  --bootstrap-server cluster-broker-0.cluster-kafka-brokers.kafka.svc:9092 \
  --topic cat-interactions \
  --from-beginning
```

You should see a continuous stream of JSON events, confirming that the producer is working correctly.

**Success Criteria:**
- PostgreSQL contains cat and visitor data
- Kafka topics are created
- Events are being produced to `cat-interactions`, `cat-wellness-iot`, and `visitor-checkins` topics

---



## Module 2: Raw Data Ingestion to Iceberg

**Goal:** Deploy a Flink job that continuously reads all Kafka events and writes them to Iceberg tables in S3, creating a permanent data lake.

**Why this matters:** You're establishing the foundation for historical analytics by ensuring all raw data is durably stored. Your real-time data isn't just for immediate alerts—it's also building a massive historical archive automatically, with no complex ETL pipelines.

### Step 1: Update S3 Configuration

Update the S3 bucket name in the Flink deployment files:

```bash
export S3_BUCKET=$(terraform -chdir=/home/ubuntu/data-on-eks/data-stacks/workshop/terraform/_local output -raw s3_bucket_id_spark_history_server)
```

### Step 2: Deploy Raw Ingestion Flink Job

Deploy the Flink job that ingests raw events to Iceberg:

```bash
export DATAHUB_TOKEN=abc
bash deploy-flink.sh
```

**Validate:** Check the Flink deployment:
```bash
kubectl get flinkdeployments -n flink-team-a
```

You should see `cat-cafe-raw-ingestion` in `READY` state.

### Step 3: Monitor Flink Job

Check that the Flink pods are running:
```bash
kubectl get pods -n flink-team-a -l app=cat-cafe-raw-ingestion
```

Wait for both JobManager and TaskManager pods to be ready.

### Step 4: Access Flink UI

Port-forward to the Flink JobManager:
```bash
kubectl port-forward -n flink-team-a \
  svc/cat-cafe-raw-ingestion-rest 8081:8081
```

Open your browser to `http://localhost:8081` to view the Flink dashboard.

![](./images/flink-raw-ui.png)

### Step 5: Verify Data Ingestion

In the Flink UI, you should see:
- A running job named "cat-cafe-raw-ingestion"
- Five source operators consuming from Kafka topics
- Five sink operators writing to Iceberg tables

**Check the job metrics:**
- Records consumed from each Kafka topic
- Records written to Iceberg tables
- No failures or restarts

### What You Accomplished

You learned about Apache Iceberg's role as a modern data lakehouse format and deployed a Flink job that consumes from every raw Kafka topic (`visitor-checkins`, `cat-interactions`, `cat-wellness-iot`, etc) and sinks the data into corresponding Iceberg tables on S3.

**Key Takeaway:** You've created an automated pipeline that transforms streaming events into queryable historical data without complex ETL processes. Every event flowing through Kafka is now permanently stored and ready for future analytics.

**Success Criteria:**
- Flink deployment is in READY state
- Flink job is running without errors
- Data is flowing from Kafka topics to Iceberg tables
- Flink UI shows active consumption and ingestion metrics


## Module 3: Real-time Alerting with Flink

**Goal:** Deploy Flink jobs that analyze streaming data to generate intelligent alerts for cat health monitoring and adoption detection.

**Why this matters:** This is the brain of your real-time platform. You're building two distinct intelligence systems: a Cat Wellness Guardian that detects health anomalies, and an Adopter Detective that identifies potential cat adopters through behavioral analysis.

### Step 1: Deploy Alert Processing Jobs

Deploy the Flink jobs that process raw events and generate alerts:

```bash
export DATAHUB_TOKEN=abc
bash deploy-flink-alert.sh
```

**Validate:** Check both Flink deployments:
```bash
kubectl get flinkdeployments -n flink-team-a
```

You should see `cat-cafe-alerts` in `READY` state.

### Step 2: Monitor Alert Jobs

Check that the alert processing pods are running:
```bash
kubectl get pods -n flink-team-a -l app=cat-cafe-alerts
```

Wait for both JobManager and TaskManager pods to be ready.

### Step 3: Access Flink Alert UI

Port-forward to the alert job JobManager:
```bash
kubectl port-forward -n flink-team-a \
  svc/cat-cafe-alerts-rest 8082:8081
```

Open your browser to `http://localhost:8082` to view the alert processing dashboard.

### Step 4: Verify Alert Generation

In the Flink UI, you should see two running jobs:

**Cat Wellness Guardian (Stateless):**
- Filters `cat-wellness-iot` stream for anomalous readings
- Detects low activity or dehydration events
- Publishes alerts to `cat-health-alerts` topic

**Adopter Detective (Stateful):**
- Tracks visitor 'like' interactions over time
- Performs continuous aggregation to identify patterns
- Publishes potential adopters to `potential-adopters` topic

### Step 5: Test Alert Consumption

Verify alerts are being generated:
```bash
# Monitor health alerts
kubectl exec -it kafka-debug-pod -n workshop -- \
  kafka-console-consumer \
  --bootstrap-server cluster-broker-0.cluster-kafka-brokers.kafka.svc:9092 \
  --topic cat-health-alerts \
  --from-beginning

# Monitor adoption alerts (in another terminal)
kubectl exec -it kafka-debug-pod -n workshop -- \
  kafka-console-consumer \
  --bootstrap-server cluster-broker-0.cluster-kafka-brokers.kafka.svc:9092 \
  --topic potential-adopters \
  --from-beginning
```

### What You Accomplished

You built the brain of the real-time platform by deploying two distinct Flink SQL jobs that process raw streams and generate valuable, actionable alerts:

- **The Cat Wellness Guardian:** A stateless job that filters wellness IoT data for health anomalies
- **The Adopter Detective:** A stateful job that tracks visitor interactions and identifies adoption patterns

**Key Takeaway:** You experienced the power of Flink to analyze data in motion, handling both simple filtering and complex, stateful aggregations that remember past events. Your streaming platform now generates intelligent alerts from raw sensor data.

**Success Criteria:**
- Alert processing Flink deployment is in READY state
- Both wellness and adoption detection jobs are running
- Health alerts appear in `cat-health-alerts` topic
- Adoption alerts appear in `potential-adopters` topic
- Flink UI shows processing metrics for both jobs

---



## Module 4: Live Alert Dashboard

**Goal:** Deploy a web application that visualizes real-time alerts and demonstrates the complete data loop from events to UI.

**Why this matters:** This is where the platform comes to life. You're connecting abstract data processing to a tangible, human-facing interface that shows alerts in real-time and can even trigger actions back to the source systems.

### Step 1: Deploy the Web UI

Deploy the live dashboard application:

```bash
kubectl apply -f $WORKSHOPDIR/manifests/webui.yaml
```

**Validate:** Check the web UI deployment:
```bash
kubectl get pods -n workshop -l app=alert-ui
```

### Step 2: Access the Dashboard

Port-forward to the web application:
```bash
kubectl port-forward -n workshop svc/alert-ui 8088:8080
```

Open your browser to `http://localhost:8088`

![](./images/alert-webui.png)

### Step 3: Observe Real-time Alerts

In the dashboard, you should see:
- **Live Cafe Feed:** Real-time alerts appearing on the right side
- **Cat Status Grid:** Current status of all cats in the cafe
- **Alert Types:** Both health alerts and adoption notifications

### What You Accomplished

You deployed and accessed the "Live Dashboard" web application that consumes alerts from Kafka via WebSockets. You watched as health and adopter alerts generated by your Flink jobs appeared in the "Live Cafe Feed" in real-time.

**Key Takeaway:** The Flink jobs you wrote are now pushing notifications to a web browser, which can even influence the original data source. You've built a complete, interactive, end-to-end data loop.

**Success Criteria:**
- Web UI is accessible at localhost:8088
- Real-time alerts appear in the Live Cafe Feed
- Cat status updates reflect adoption events
- Dashboard shows both health and adoption alerts

---

## Module 5: Batch Dimension Data Ingestion

**Goal:** Use Spark to ingest dimension data (cats and visitors profiles) from PostgreSQL into Iceberg tables for analytical queries.

**Why this matters:** To enrich your analytical queries, you need dimension data. This batch process creates snapshots of operational data that can be joined with your streaming event data for comprehensive analysis.

### Step 1: Access JupyterHub

Port-forward to the JupyterHub service:
```bash
kubectl port-forward -n jupyterhub svc/proxy-public 8000:80
```

Open your browser to `http://localhost:8000`

### Step 2: Start Spark Environment

1. Select the **Spark 4.0** image from the dropdown
2. Click **Start**
3. Wait for Karpenter to provision a node (this may take 2-3 minutes)

![](./images/jupyter-image-selection.png)

### Step 3: Run Dimension Ingestion

Copy the dimension ingestion script to your Jupyter environment:
```bash
POD_NAME=$(kubectl get pods -n jupyterhub -l app=jupyterhub,component=singleuser-server -o jsonpath='{.items[0].metadata.name}') && kubectl cp /home/ubuntu/data-on-eks/data-stacks/workshop/src/spark/adhoc.ipynb jupyterhub/$POD_NAME:/home/jovyan/adhoc.ipynb

cp /home/jovyan/data-stacks/workshop/src/spark/postgresql-to-iceberg.py .
```

Execute the script to ingest cats and visitors data:
```python
# Run the postgresql-to-iceberg.py script
# This will create iceberg.workshop.cats and iceberg.workshop.visitors tables
```

### What You Accomplished

You used a batch Spark job to take snapshots of the `cats` and `visitors` tables from the operational PostgreSQL database and wrote them into Iceberg tables, creating dimension data for analytical queries.

**Success Criteria:**
- JupyterHub environment is running
- Spark session connects successfully
- Iceberg tables `cats` and `visitors` are created
- Data is successfully ingested from PostgreSQL

---

## Module 6: Batch Analytics & Transformation

**Goal:** Act as a data analyst using Spark to query historical data, join multiple tables, and create aggregated summary tables.

**Why this matters:** You're leveraging the historical data collected in your Iceberg data lake to perform deeper analysis, joining streaming events with dimension data to create business insights.

### Step 1: Open Analytics Notebook

In your Jupyter environment, open the analytics notebook:
```bash
POD_NAME=$(kubectl get pods -n jupyterhub -l app=jupyterhub,component=singleuser-server -o jsonpath='{.items[0].metadata.name}') && kubectl cp /home/ubuntu/data-on-eks/data-stacks/workshop/src/spark/adhoc.ipynb jupyterhub/$POD_NAME:/home/jovyan/adhoc.ipynb
```

### Step 2: Execute Analysis Queries

Follow the notebook instructions to:
1. **Connect to Iceberg:** Query raw event tables and dimension tables
2. **Join Data:** Combine cat interactions with cat profiles
3. **Aggregate Metrics:** Calculate daily summaries and adoption patterns
4. **Create Summary Tables:** Build `daily_cat_summary` for BI reporting

### Step 3: Validate Results

Verify your analytical transformations:
```sql
-- Check the summary table was created
SHOW TABLES IN iceberg.workshop;

-- Query sample results
SELECT * FROM iceberg.workshop.daily_cat_summary LIMIT 10;
```

### What You Accomplished

You connected to the Iceberg data lake with Spark, queried raw historical data, joined multiple tables to find insights, and created clean, aggregated summary tables ready for business intelligence reporting.

**Key Takeaway:** Your streaming platform now supports both real-time alerts and historical batch analytics on the same data, demonstrating the power of a unified lakehouse architecture.

**Success Criteria:**
- Successfully query raw Iceberg tables
- Join streaming events with dimension data
- Create aggregated `daily_cat_summary` table
- Validate data quality and completeness

---


**Module 7: Advanced Iceberg Features**
* **Overview:** We explore the powerful features that make Iceberg a true lakehouse. Using Spark SQL, we learn how to inspect table metadata and history, perform "time travel" queries to see past versions of our data, and demonstrate safe schema evolution by adding a column to our summary table.
* **Status:** **WIP**

**Module 8: BI Dashboard with Superset**
* **Overview:** The final piece of the platform is the business intelligence dashboard for our cafe "manager." This involves connecting a BI tool like Apache Superset to our data lake to create visualizations and reports based on the clean summary tables we built.
* **Status:** **WIP**
