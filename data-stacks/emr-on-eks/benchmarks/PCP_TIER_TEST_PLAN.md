# EMR on EKS PCP Tier Test Plan

## Goal

Measure how many EMR on EKS Spark jobs each EKS PCP tier can sustain before control-plane limits become the bottleneck.

Tiers in scope:

- `XL`
- `2XL`
- `4XL`
- `8XL`

Primary question:

- For each PCP tier, what submission rate can we run without hitting API server pressure, etcd growth pressure, or EMR `StartJobRun` throttling?

## Test Method

For each PCP tier:

1. Start from a known-clean state with `0` active EMR jobs.
2. Run the benchmark against the EMR on EKS gamma endpoint.
3. Start at the first planned submission target.
4. Increase the target jobs/min in steps.
5. Stop when we hit the ceiling for that tier.
6. Move to the next PCP tier and repeat the same sequence.

## Initial Step Sequence

The first tier under active testing is `4XL`.

Initial submission-rate steps:

1. `100 jobs/min`
2. `200 jobs/min`
3. `300 jobs/min`

If `300 jobs/min` is still clean, add another step sequence after reviewing the data.

## Ceiling Criteria

Treat the current step as the ceiling when any of the following happens:

- EMR `StartJobRun` begins returning `TooManyRequestsException`
- API server PCP metrics approach or exceed the tier threshold
- etcd size approaches or exceeds the tier threshold
- pod scheduling pressure becomes unstable enough that observed throughput stops tracking requested throughput
- the cluster does not drain cleanly after the run

The acceptable step for a tier is the highest step below the first failing or unstable step.

## Metrics To Capture

For every run, capture:

- requested submission target in `jobs/min`
- actual `start_job_run` rate from Locust
- EMR API failures and throttling signals
- observed jobs/min in Grafana
- peak pod scheduling rate
- peak running pods
- peak node count
- PCP API server seats or equivalent API pressure signal
- etcd size or equivalent storage pressure signal
- active jobs at start and end of run

## Run Discipline

- Use the same Spark job shape across tiers unless the benchmark definition is intentionally changed.
- Keep the same query set across tiers for comparable results.
- Wait for all prior jobs to reach terminal state before the next run.
- Record the exact endpoint used for each run.
- Record both the requested submission rate and the observed cluster rate.

## Current Benchmark Definition

Current opinionated job shape:

- Queries: `q4-v2.4,q24a-v2.4,q24b-v2.4,q67-v2.4`
- Iterations: `1`
- Scale factor: `1000`
- Executors/job: `30`
- Executor cores/memory: `2 / 5g`
- Driver cores/memory: `1 / 2g`

## Current Execution Order

1. `4XL` at `100 jobs/min`
2. `4XL` at `200 jobs/min`
3. `4XL` at `300 jobs/min`
4. Review the `4XL` ceiling
5. Move to the next PCP tier and repeat
