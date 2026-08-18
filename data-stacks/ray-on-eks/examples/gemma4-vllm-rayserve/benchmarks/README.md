# Gemma 4 benchmark suite

Measures cold and warm-prefix latency, fixed decode, prefill, and throughput at
concurrency 1, 4, 8, and 16. Every test has a separate executable request file
and produces a separate local JSON artifact.

Published results and interpretation live in the
[Gemma 4 12B GPU benchmark](https://awslabs.github.io/data-on-eks/docs/benchmarks/gemma-4-12b-rayserve-gpu-benchmark)
on the Data on EKS website. This file is the execution runbook.

## Prerequisites

Run commands from `gemma4-vllm-rayserve/`:

```bash
export KUBECONFIG=<repo>/data-stacks/ray-on-eks/kubeconfig.yaml
export S3_BUCKET=<existing-private-model-bucket>
export AWS_REGION=us-west-2
export SCENARIO=DEP-L40-BASE

./deploy.sh prepare "$SCENARIO" # once per model variant
./deploy.sh service "$SCENARIO"
kubectl get rayservice -n raydata -w
./deploy.sh test "$SCENARIO"
```

`./deploy.sh scenarios` lists all supported configurations. H100 scenarios
require the isolated Capacity Block resources described in the parent README.

## Prompt inputs

The supplied prompts live in `prompts/`, one user message per file. That folder
is ignored because customer inputs must remain local. Do not rename or edit the
prompt corpus during a comparison.

## Run one test

```bash
./benchmarks/requests/T03-cold-latency.sh "$SCENARIO"
./benchmarks/requests/T04-warm-latency.sh "$SCENARIO"
./benchmarks/requests/T05-fixed-decode.sh "$SCENARIO"
./benchmarks/requests/T06-prefill.sh "$SCENARIO"
./benchmarks/requests/T07-throughput-c01.sh "$SCENARIO"
./benchmarks/requests/T08-throughput-c04.sh "$SCENARIO"
./benchmarks/requests/T09-throughput-c08.sh "$SCENARIO"
./benchmarks/requests/T10-throughput-c16.sh "$SCENARIO"
```

## Run the full T03-T10 suite

Start the continuation runner, then T03. The runner waits for a structurally
valid T03 artifact before executing T04-T10 serially:

```bash
./run-scenario-after-t03.sh "$SCENARIO" &
./benchmarks/requests/T03-cold-latency.sh "$SCENARIO"
```

Do not run two tests against the same GPU simultaneously. Scenarios may run in
parallel only when they use separate physical GPUs. The harness selects the
scenario-specific Ray head and worker using `app=<service-name>` labels.

## Test definitions

| Test | Purpose | Requests |
|---|---|---:|
| T03 | Cold-prefix latency, concurrency 1 | 60 |
| T04 | Warm-prefix latency after per-prompt priming | 60 |
| T05 | Fixed 512-token decode | 60 |
| T06 | One-token prefill | 60 |
| T07 | Fixed decode, concurrency 1 | 36 |
| T08 | Fixed decode, concurrency 4 | 72 |
| T09 | Fixed decode, concurrency 8 | 96 |
| T10 | Fixed decode, concurrency 16 | 192 |

Warm-prefix priming is performed independently for each prompt so similar A/B
prompt files cannot silently prewarm one another. Cold requests receive a
unique leading nonce to invalidate the prefix cache.

## Results and validation

Artifacts are written to:

```text
benchmarks/results/<SCENARIO>/<TEST>-<UTC timestamp>.json
```

`benchmarks/results/` is ignored and must remain unstaged because artifacts
contain model responses derived from customer prompts. The JSON includes the
run configuration, completion marker, six prompt summaries, and every raw
request record. Results checkpoint after every prompt so a disconnected client
does not discard completed GPU work.

An accepted artifact must have:

- `complete: true`;
- the expected scenario and test ID;
- model identity and immutable image digest matching the rendered scenario;
- the expected instance type, GPU model, and GPU count;
- six prompt summaries with server-reported input-token counts;
- the expected raw request count from the table above;
- zero empty responses or non-empty `error` values; and
- fixed-token targets and truncation status where the test requires them.

A comparison run is valid only when the RayService is healthy before and after
the test, warm measurements exclude priming requests, and no unrelated
inference workload shares the allocated physical GPUs. Keep exact instance,
NodePool, and capacity-type selectors in place so a scenario cannot fall back to
different hardware.

T03/T04 use a 512-token output cap. If `finish_reason=length`, the latency is
valid fixed-cap performance evidence but not proof of natural-completion JSON
quality. Run a separate natural-EOS quality evaluation before selecting QAT.

## Cleanup

```bash
./deploy.sh cleanup "$SCENARIO"
kubectl delete nodeclaim -l karpenter.sh/nodepool=gpu # optional immediate release
```

For H100 Capacity Block scenarios, preserve and validate all evidence first,
then remove the benchmark-only resources:

```bash
kubectl delete nodepool gpu-capacity-block --ignore-not-found
kubectl delete ec2nodeclass gpu-capacity-block --ignore-not-found
```
