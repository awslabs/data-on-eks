# Gemma 4 benchmark suite

Measures cold and warm-prefix latency, fixed decode, prefill, and throughput at
concurrency 1, 4, 8, and 16. Every test has a separate executable request file
and produces a separate local JSON artifact.

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
- six prompt summaries;
- the expected raw request count from the table above; and
- zero non-empty `error` values.

T03/T04 use a 512-token output cap. If `finish_reason=length`, the latency is
valid fixed-cap performance evidence but not proof of natural-completion JSON
quality. Run a separate natural-EOS quality evaluation before selecting QAT.

## Cleanup

```bash
./deploy.sh cleanup "$SCENARIO"
kubectl delete nodeclaim -l karpenter.sh/nodepool=gpu # optional immediate release
```

For H100 Capacity Block scenarios, preserve and validate all evidence first,
then remove the benchmark-only pool with `./manage-capacity-block.sh delete`.
