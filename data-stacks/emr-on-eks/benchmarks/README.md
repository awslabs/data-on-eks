# EMR on EKS PCP Benchmark Runbook

This directory contains the benchmark assets used to validate an EMR on EKS Spark deployment and exercise EKS PCP limits on a 4XL control plane.

## Files

- `setup_benchmark.sh`: one-time setup for the benchmark image, pod templates, and Prometheus rules
- `benchmark.sh`: single wrapper script to start, stop, and inspect benchmark runs
- `benchmark.env.example`: example local config file for cluster-specific benchmark inputs
- `locustfile.py`: load generator for concurrent EMR on EKS job submissions
- `PCP_TIER_TEST_PLAN.md`: tier-by-tier benchmark plan and stopping criteria
- `JOB_EXECUTION_RESULTS.md`: single output document for all benchmark runs
- `driver-pod-template.yaml` and `executor-pod-template.yaml`: Spark pod templates uploaded to S3 before submission
- `prometheus-pcp-rules.yaml`: Prometheus recording rules and alerts for PCP monitoring
- `Dockerfile`: multi-arch benchmark image build

## Prerequisites

- The EMR on EKS stack is already deployed under `data-stacks/emr-on-eks/terraform/_local`
- Local tools: `terraform`, `jq`, `aws`, `kubectl`
- AWS credentials point to the target account and region
- The benchmark image URI and input dataset path are configured in local `benchmark.env`

## Important variable

The scripts default to the team value in `benchmark.env`.

If you want a different EMR virtual cluster, export:

```bash
export EMR_TEAM=<emr-team>
```

The benchmark scripts are hardcoded to the EMR on EKS gamma endpoint:

```bash
https://emr-containers-gamma.<aws-region>.amazonaws.com
```

The benchmark wrapper reads cluster-specific runtime values from a local `benchmark.env` file. Keep that file local so bucket names, ARNs, and related environment details do not need to be committed.

## One-time setup

Before running the benchmark, create a local config file:

```bash
cp benchmark.env.example benchmark.env
```

Fill in the environment-specific values in `benchmark.env`.
That file is intended to stay local so bucket names, ARNs, and other runtime details do not need to be committed.

Run from this directory:

```bash
./setup_benchmark.sh
```

This does four things:

1. Builds and pushes the benchmark image to ECR
2. Uploads the pod templates to S3
3. Applies Prometheus PCP rules if the `monitoring` namespace exists
4. Prints the environment variables required by Locust

## Benchmark control

Run from this directory:

```bash
./benchmark.sh start
```

What it does:

- Reads the cluster-specific runtime values from local `benchmark.env`
- Uploads the pod templates to `s3://<bucket>/pcp-benchmarks/scripts/`
- Starts Locust in the background with the benchmark settings defined at the top of `benchmark.sh`
- Uses the same wrapper for a 1-job smoke run or a sustained high-volume run by changing the variables at the top of the file
- Tracks submitted and active EMR job IDs under `.benchmark-state/`
- Allows `./benchmark.sh stop` to stop Locust and cancel any still-active EMR jobs gracefully

Default benchmark query subset:

```text
q4-v2.4,q24a-v2.4,q24b-v2.4,q67-v2.4
```

Useful commands:

```bash
./benchmark.sh start
./benchmark.sh status
./benchmark.sh stop
```

Only a small set of tunables live at the top of `benchmark.sh`:

- `LOCUST_USERS`
- `LOCUST_SPAWN_RATE`
- `LOCUST_RUN_TIME`
- `MAX_JOBS_TO_SUBMIT`
- `TPCDS_QUERIES`

Everything else is intentionally hardcoded in the script so the benchmark stays opinionated and comparable across runs.

Examples:

- First planned `4XL` run: `LOCUST_USERS=3000`, `LOCUST_SPAWN_RATE=1.67`, `LOCUST_RUN_TIME=30m`, `MAX_JOBS_TO_SUBMIT=3000`
- Next `4XL` steps: raise the target to the `200 jobs/min` and `300 jobs/min` settings after recording the prior result

The benchmark config sets Spark scratch space to:

```text
/var/data/spark-local
```

Do not place that path under `/tmp`. EMR on EKS reserves `/tmp` internally and rejects user pod templates that overlap it.

Also do not add a manual volume mount for that path in the pod templates. EMR on EKS injects the local-dir mount itself when `spark.local.dir` is set.

## Common failure modes

### `EMR Virtual Cluster : null`

Cause:

- The script is parsing Terraform outputs with an outdated JSON path

Fix:

- Use the updated scripts in this directory

### `Could not connect to the endpoint URL`

Cause:

- Local AWS/S3 connectivity issue, proxy/VPN issue, or a restricted execution environment

Checks:

```bash
aws sts get-caller-identity
aws s3 ls <your-benchmark-bucket>
```

### Job reaches `FAILED`

Collect details:

```bash
aws emr-containers describe-job-run \
  --virtual-cluster-id <virtual-cluster-id> \
  --id <job-run-id> \
  --region <aws-region> \
  --endpoint-url https://emr-containers-gamma.<aws-region>.amazonaws.com | jq '.jobRun | {state, failureReason, stateDetails}'
```

Then inspect:

- CloudWatch log group for the selected EMR team
- Spark driver/executor pods in namespace `emr-data-team-a`
- uploaded pod templates under `s3://<bucket>/pcp-benchmarks/scripts/`

### `Defined volume mount path on main container must not overlap with reserved mount paths: [/tmp]`

Cause:

- The driver or executor pod template mounts a volume somewhere under `/tmp`

Fix:

- Use a non-reserved path such as `/var/data/spark-local`
- Make sure `spark.local.dir` matches that path
- Remove any manual pod-template volume mount for the same location

## Useful debug commands

```bash
export KUBECONFIG=kubeconfig.yaml
kubectl get pods -n emr-data-team-a
kubectl get events -n emr-data-team-a --sort-by=.lastTimestamp
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
kubectl get nodeclaims
```

## Rerun flow

1. Confirm AWS access works locally
2. Run `./benchmark.sh start`
3. Use `./benchmark.sh status` during the run
4. Use `./benchmark.sh stop` to stop Locust and cancel any remaining EMR jobs
