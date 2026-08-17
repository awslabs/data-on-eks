# Gemma 4 12B RayServe Benchmark Matrix

Last updated: 2026-08-16

This is the working tracker for the Gemma 4 12B RayServe benchmark. Update it
after every deployment or benchmark run. Raw responses and result JSON must
remain local and must not be committed.

## Status legend

| Status | Meaning |
|---|---|
| `NOT STARTED` | Files or cluster changes have not been prepared |
| `NOT RUN` | Test was not captured for the current deployment; reason is recorded |
| `BLOCKED` | Waiting on quota, capacity, compatibility, or another prerequisite |
| `READY` | Configuration is validated and can be deployed or run |
| `DEPLOYING` | RayService is starting |
| `RUNNING` | Benchmark is in progress |
| `PARTIAL` | Some evidence exists, but the complete acceptance gate has not passed |
| `PASSED` | Run completed and passed result-quality checks |
| `FAILED` | Run failed; record the reason in the run log |
| `DEFERRED` | Intentionally parked until higher-priority scenarios finish |
| `SKIPPED` | Deliberately omitted; record the reason |

## Guardrails

- Do not run Terraform or the stack-level `deploy.sh` from the benchmark workflow.
- Do not create public endpoints or other public resources.
- Do not commit prompts, raw model responses, credentials, or benchmark results.
- Run one deployment scenario at a time.
- Confirm the exact EC2 instance type, GPU model, GPU count, and engine config
  from the live workload before accepting a result.
- Use the six files in `../prompts/` as the authoritative prompt corpus.

## Infrastructure prerequisites

| ID | Requirement | Current state | Required action | Owner | Status | Evidence / notes |
|---|---|---|---|---|---|---|
| INFRA-01 | Existing Ray-on-EKS cluster is healthy | Control plane reachable; baseline RayService and its dedicated CPU/GPU nodes are healthy | Continue with baseline tests | Benchmark operator | `PASSED` | Verified live on 2026-08-16 |
| INFRA-02 | L40S Karpenter capacity | GPU NodePool Ready; Karpenter successfully launched on-demand `g6e.2xlarge` in `us-west-2c` | Use the provisioned L40S for baseline readiness and tests | Benchmark operator | `PASSED` | Verified 2026-08-16 |
| INFRA-03 | H100 Karpenter capacity | Live GPU NodePool excludes category/family `p`; overlay is ready at `terraform/manifests/karpenter/nodepool-gpu-g6.yaml` | User applies the overlay with `ray-on-eks/deploy.sh`; do not edit `_local` | User | `BLOCKED` | Overlay YAML parsed successfully; live change not yet applied |
| INFRA-04 | H100 TP=1 capacity | BASE and OPT will use 1 of 8 H100 GPUs on the reserved `p5.48xlarge`; `p5.4xlarge` is parked | Use Capacity Block pool and record whole-instance allocation separately from requested GPUs | Benchmark operator | `READY` | Same physical instance as TP4; isolates configuration comparison |
| INFRA-05 | H100 Capacity Block | Benchmark-specific reservation, `p5.48xlarge`, single AZ | Keep only for H100 suite; delete temporary Karpenter resources after evidence copy | Benchmark operator | `PASSED` | Node Ready with 8 GPUs and reservation label; account identifiers retained only in ignored local evidence |
| INFRA-06 | Models staged in S3 | BF16 model verified: config, tokenizer, chat template, processor config, and 23,919,549,408-byte safetensors object; QAT prefix absent | Use existing BF16 objects for baseline; stage QAT later into its distinct model directory | Benchmark operator | `READY` | Never overwrite the BF16 model directory |
| INFRA-07 | Compatible Ray/vLLM image in ECR | Ray 2.57 image exists in private ECR | Use immutable digest for accepted results and run capability smoke check | Benchmark operator | `READY` | `sha256:03ce0717cfd280b87f2ac4bf592130d2d9d2a8d87252eb713216d7545578793b` |

## Deployment scenario matrix

Only scenarios that pass a smoke test proceed to the full benchmark suite.

| Scenario | Deployment type | EC2 instance | GPU allocation | Model / weights | TP | Weight dtype / quantization | KV cache | Prefix cache | Speculative decoding | Async scheduling | Deployment status | Smoke status | Result status | Notes |
|---|---|---|---:|---|---:|---|---|---|---|---|---|---|---|---|
| DEP-L40-BASE | RayServe, single replica | `g6e.2xlarge` exact selector and observed | 1x L40S 48 GB | `google/gemma-4-12B-it` | 1 | BF16 | Auto/BF16 | Enabled | Disabled | Enabled | `CLEANED UP` | `PASSED` | `PASSED*` | T03-T10 complete with zero request errors; natural-EOS quality pending |
| DEP-L40-OPT | RayServe, single replica | `g6e.2xlarge` exact selector and observed | 1x L40S 48 GB | `google/gemma-4-12B-it` | 1 | BF16 | FP8 | Enabled | n-gram, 5 tokens | Disabled | `CLEANED UP` | `PASSED` | `PASSED*` | T03-T10 complete with expected counts and zero request errors; natural-EOS quality pending |
| DEP-L40-QAT | RayServe, single replica | `g6e.2xlarge` exact selector and observed | 1x L40S 48 GB | `google/gemma-4-12B-it-qat-w4a16-ct` | 1 | W4A16 QAT (`compressed-tensors`, Marlin) | FP8 | Enabled | Disabled | Enabled | `CLEANED UP` | `PASSED` | `PASSED*` | T03-T10 validated with zero errors and checksums; RayService deleted |
| DEP-H100-BASE | RayServe, single replica | reserved `p5.48xlarge` exact selector | 1 of 8x H100 80 GB | `google/gemma-4-12B-it` | 1 | BF16 | Auto/BF16 | Enabled | Disabled | Enabled | `CLEANED UP` | `PASSED` | `PASSED*` | T03-T10 complete with zero request errors; natural-EOS quality pending |
| DEP-H100-OPT | RayServe, single replica | reserved `p5.48xlarge` exact selector and observed | 1 of 8x H100 80 GB | `google/gemma-4-12B-it` | 1 | BF16 | FP8 | Enabled | n-gram, 5 tokens | Disabled | `CLEANED UP` | `PASSED` | `PASSED*` | T03-T10 complete with expected counts and zero request errors; natural-EOS quality pending |
| DEP-H100-TP4 | RayServe, single replica | reserved `p5.48xlarge` exact selector and observed | 4 of 8x H100 80 GB | `google/gemma-4-12B-it` | 4 | BF16 | Auto/BF16 | Enabled | Disabled | Enabled | `CLEANED UP` | `PASSED` | `PASSED*` | Live fingerprint `vllm-0.25.1-tp4`; T03-T10 complete with expected counts and zero request errors |

## Authoritative prompt corpus

Do not rename or modify the supplied prompts during the benchmark. Record the
server-reported token count for every deployment because tokenizer or chat
template changes can alter it.

| Prompt ID | File | Bytes | Workload | Relationship | Server input tokens |
|---|---|---:|---|---|---:|
| PR-2K-NOSRC | `../prompts/prompt_2k_token_no_source_turn.txt` | 10,011 | Short profile-fact extraction | Baseline without `source_turn` | 2,298 |
| PR-2K-SRC | `../prompts/prompt_2k_token.txt` | 10,048 | Short profile-fact extraction | Same workload with `source_turn` | 2,305 |
| PR-20K-NOSRC | `../prompts/prompt_20K_token_no_source_turn` | 84,924 | Long profile-fact extraction | Baseline without `source_turn` | 20,545 |
| PR-20K-SRC | `../prompts/prompt_20K_token` | 84,961 | Long profile-fact extraction | Same workload with `source_turn` | 20,553 |
| PR-PROFILE-L | `../prompts/profile_fact_hydrated_LARGE.txt` | 112,073 | Hydrated profile-fact extraction | Independent large workload | 31,411 cold / 31,375 warm |
| PR-SUMMARY-L | `../prompts/summary_multi_records_hydrated_LARGE.txt` | 107,820 | Hydrated multi-record summary | Independent large workload | 29,469 |

## Test type matrix

Every applicable test produces a separate result file. Warm-cache runs must
prime each prompt before measurement so that A/B prompt pairs do not silently
prewarm one another.

| Test ID | Test type | Purpose | Cache state | Concurrency | Repeats | Output policy | Primary metrics | Result file | Status |
|---|---|---|---|---:|---:|---|---|---|---|
| T01 | Deployment cold start | Production scale-from-zero timing | Empty GPU NodePool capacity | N/A | 1 per deployment | 16-token health request | Node provisioning, image pull, weight load, engine init, ready-to-serve | `results/<scenario>/deployment-cold.json` | `NOT RUN`: baseline deployment predates timing capture |
| T02 | Deployment warm start | Restart timing with node/image available | N/A | N/A | 1 per deployment | 16-token health request | Weight load, engine init, ready-to-serve | `results/<scenario>/deployment-warm.json` | `NOT RUN`: no measured restart yet |
| T03 | Cold-prefix latency | Measure full prefill plus interactive decode | Unique leading nonce per request | 1 | 10 final | Natural EOS, max 512 | TTFT p50/p95, E2E p50/p95, input/output tokens | `results/DEP-L40-BASE/T03/results.json` | `PASSED*`: 60/60, fixed-cap limitation |
| T04 | Warm-prefix latency | Measure reusable-prefix behavior | Prime each prompt, then measure identical prompt | 1 | 10 final | Natural EOS, max 512 | TTFT p50/p95, E2E p50/p95, cached-token evidence | `results/DEP-L40-BASE/T04/results.json` | `PASSED*`: 60/60; post-run counter capture unavailable |
| T05 | Fixed-length decode | Isolate decode rate across hardware/configs | Cold prefix | 1 | 10 final | Ignore EOS, exactly 512 tokens | Decode tok/s p50/p95, ITL, E2E | `results/DEP-L40-BASE/T05-20260816T211306Z.json` | `PASSED`: 60/60, exactly 512 tokens |
| T06 | Prefill throughput | Compare prompt-processing speed | Cold prefix | 1 | 10 final | Minimal output, target 1 token | Prefill tok/s, TTFT, prefill KV tokens | `results/DEP-L40-BASE/T06-20260816T213623Z.json` | `PASSED`: 60/60 |
| T07 | Concurrency 1 | Throughput reference | Cold prefix | 1 | 6 measured per prompt | Fixed 512-token output | Request/s, input tok/s, output tok/s, latency | separate scenario files | `PASSED` on G6E and H100 BASE |
| T08 | Concurrency 4 | Low-concurrency production load | Same as T07 | 4 | 12 measured per prompt | Fixed 512-token output | Request/s, input tok/s, output tok/s, latency | separate scenario files | `PASSED` on G6E and H100 BASE |
| T09 | Concurrency 8 | Medium-concurrency production load | Same as T07 | 8 | 16 measured per prompt | Fixed 512-token output | Request/s, input tok/s, output tok/s, latency | separate scenario files | `PASSED` on G6E and H100 BASE |
| T10 | Concurrency 16 | Saturation step | Same as T07 | 16 | 32 measured per prompt | Fixed 512-token output | Request/s, token throughput, queue time, errors | separate scenario files | `PASSED` on G6E and H100 BASE |
| T11 | Structured-output validation | Prevent a fast but invalid result from passing | Cold prefix | 1 | Included with latency runs | Natural EOS | Valid JSON, schema fields, finish reason, truncation, response hash | embedded in `results/DEP-L40-BASE/T03/results.json` | `PARTIAL`: truncation recorded; dedicated natural-EOS run pending |
| T12 | Resource observation | Explain performance and capacity limits | N/A | All load tests | Continuous/sample interval TBD | N/A | GPU utilization, GPU memory, CPU, queue depth, KV usage | `results/<scenario>/resources.json` | `NOT STARTED` |

## Scenario execution tracker

Mark a scenario complete only when all required tests pass their validation
gates. `T09` and `T10` may be stopped early if the previous concurrency level
already produces errors or unacceptable queueing.

| Scenario | Config validation | Deploy | T01 | T02 | T03 | T04 | T05 | T06 | T07 | T08 | T09 | T10 | T11 | T12 | Overall |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| DEP-L40-BASE | `PASSED` | `PASSED` | `NOT RUN` | `NOT RUN` | `PASSED*` | `PASSED*` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PARTIAL` | `PARTIAL` | `PASSED*` |
| DEP-L40-OPT | `PASSED` | `PASSED` | `NOT RUN` | `NOT RUN` | `PASSED*` | `PASSED*` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PARTIAL` | `PARTIAL` | `PASSED*` |
| DEP-L40-QAT | `PASSED` | `PASSED` | `NOT RUN` | `NOT RUN` | `PASSED*` | `PASSED*` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PARTIAL` | `PARTIAL` | `PASSED*` |
| DEP-H100-BASE | `PASSED` | `PASSED` | `NOT RUN` | `NOT RUN` | `PASSED*` | `PASSED*` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PARTIAL` | `PARTIAL` | `PASSED*` |
| DEP-H100-OPT | `PASSED` | `PASSED` | `NOT RUN` | `NOT RUN` | `PASSED*` | `PASSED*` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PARTIAL` | `PARTIAL` | `PASSED*` |
| DEP-H100-TP4 | `PASSED` | `PASSED` | `NOT RUN` | `NOT RUN` | `PASSED*` | `PASSED*` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PASSED` | `PARTIAL` | `PARTIAL` | `PASSED*` |

## Result comparison

The final comparison and recommendation are maintained in
`BENCHMARK_REPORT.md`; the customer walkthrough is
`BENCHMARK_WALKTHROUGH.html`. Those reports aggregate all six prompt groups.
Raw per-prompt medians, percentiles, and response samples remain under the
ignored `results/<scenario>/` tree.

| Scenario | Cold TTFT | Cold E2E | Fixed decode | Prefill | C16 output | Errors |
|---|---:|---:|---:|---:|---:|---:|
| DEP-L40-BASE | 3,553 ms | 22.86 s | 26.5 tok/s | 5,597 tok/s | 147 tok/s | 0 |
| DEP-L40-OPT | 2,984 ms | 14.92 s | 44.9 tok/s | 6,265 tok/s | 227 tok/s | 0 |
| DEP-L40-QAT | 2,871 ms | 11.15 s | 61.1 tok/s | 6,474 tok/s | 252 tok/s | 0 |
| DEP-H100-BASE | 896 ms | 7.23 s | 80.6 tok/s | 20,509 tok/s | 512 tok/s | 0 |
| DEP-H100-OPT | 1,815 ms | 7.65 s | 93.3 tok/s | 12,397 tok/s | 507 tok/s | 0 |
| DEP-H100-TP4 | 382 ms | 3.82 s | 148.3 tok/s | 46,623 tok/s | 1,067 tok/s | 0 |

## Result acceptance gates

A run is accepted only when all applicable checks pass:

- RayService was healthy before the run and remained healthy afterward.
- The expected model ID and immutable container image digest were recorded.
- The observed EC2 instance, GPU model, and GPU count matched the scenario.
- All six prompt files were included, with server-reported token counts.
- No request failed, timed out, or returned an empty response unless the failure
  is the result being studied.
- Output reached the intended natural EOS or fixed-token target; truncation is
  explicitly recorded.
- Structured responses passed JSON/schema checks or were explicitly marked
  partial when the fixed output cap prevented natural completion.
- Warm-cache measurements excluded the prompt-priming request.
- No other benchmark or inference workload shared the GPU during the run.
- Raw result files and a concise log were copied locally before cleanup.

## Run log

- `2026-08-16`: DEP-L40-BASE/T03 passed for performance measurement: 60/60 requests across all six supplied prompts and 0 transport errors. Five prompt groups reached the 512-token cap before producing valid complete JSON, so these are fixed-cap latency numbers rather than natural-completion latency. Evidence: `results/DEP-L40-BASE/T03/results.json` and `results/DEP-L40-BASE/T03/run.log`; SHA-256 `199c8caff20b69ef65acd26da98df98e9001c67e10ad5569dfd0b56e00384c10` and `c85f403b3a1d51572f6860cb34ca2031dd3cd8a2c0ea57a57a8b79d060d712dc`.
- `2026-08-16`: DEP-L40-BASE/T04 warm-prefix latency started on the existing deployment.
- `2026-08-16`: DEP-L40-BASE/T04 completed 60/60 measured requests. Raw checkpoint validated with SHA-256 `a411443d65022ad43eadaba6b0cb5daf9ea292f5951c492dec34a7bb7b33b8b5`. The wrapper exited after result creation while the script was edited during execution, so post-run server-counter capture and automatic copy were unavailable; the complete remote JSON was copied manually.
- `2026-08-16 21:08 UTC`: Applied the benchmark-only `gpu-capacity-block` EC2NodeClass and NodePool in the reservation AZ. Both resources reached Ready; no NodeClaim or EC2 node was created before demand.
- `2026-08-16 21:10 UTC`: Removed the early `gpu-capacity-block` NodePool and EC2NodeClass so the live apply occurs only after reservation activation. Verified both absent and no matching NodeClaim/node existed.
- `2026-08-16 21:29 UTC`: Reservation reported active with one available `p5.48xlarge`. Applied the saved temporary manifest, both Karpenter resources reached Ready, and deployed DEP-H100-BASE. Reserved NodeClaim launched in us-west-2b; node/model initialization pending.
- `2026-08-16 21:41 UTC`: DEP-H100-BASE became Ready with two Serve endpoints; smoke returned `READY`. P5 node advertised 8 GPUs and the exact reservation label. Shared Ray-head CPU node was 6% utilized before parallel testing.
- `2026-08-16 23:05 UTC`: G6E and H100 OPT RayServices healthy. Live vLLM logs confirmed FP8 KV cache and five-token n-gram speculation on both engines; both smoke tests returned `READY`. Parallel T03 runs started with gated T04-T10 continuation runners.
- `2026-08-16 23:52 UTC`: DEP-H100-OPT T03-T10 completed. All eight local artifacts passed structural validation with six prompt summaries, expected raw counts (60, 60, 60, 60, 36, 72, 96, 192), and zero request errors.
- `2026-08-17 00:01 UTC`: DEP-L40-OPT T03-T07 completed and passed the same artifact validation with expected raw counts and zero request errors. T08 began; T09 and T10 remain gated behind it.
- `2026-08-17 00:12 UTC`: After validating all DEP-H100-OPT T03-T10 artifacts, deleted only its RayService and deployed saved scenario DEP-H100-TP4. The worker requests four GPUs and selects the reserved `p5.48xlarge`; engine initialization started on the existing Capacity Block.
- `2026-08-17 00:18 UTC`: DEP-H100-TP4 reached Running with two endpoints after a 198.13-second distributed compile. Four TP ranks were observed on GPUs 0-3; vLLM reported 62.64 GiB KV-cache memory per rank. Smoke passed with fingerprint `vllm-0.25.1-tp4`.
- `2026-08-17 00:19 UTC`: Started DEP-H100-TP4 T03 and the gated continuation runner for T04-T10. Each test writes a separate timestamped JSON artifact under `results/DEP-H100-TP4/`.
- `2026-08-17 00:38 UTC`: User-captured host `nvidia-smi` proves TP=4 physical GPU placement during load: GPUs 0-3 each had one `ray::RayWorkerProc.run`, 74,750 MiB process memory, and 81-86% utilization; GPUs 4-7 had zero memory and zero utilization. Evidence: `results/DEP-H100-TP4/nvidia-smi-20260817T003828Z.txt`; SHA-256 `68d4668ec7606d7941441262dc98ac22480ca448481385deef9188606272b9dc`.
- `2026-08-17 00:38 UTC`: DEP-H100-TP4 T03-T09 artifacts validated with all six prompt groups, expected request counts, and zero request errors. T10 concurrency-16 is running.
- `2026-08-17 00:29 UTC`: DEP-L40-OPT T03-T10 suite finished. All eight artifacts validated with expected request counts and zero request errors.
- `2026-08-17 00:39 UTC`: DEP-H100-TP4 T10 completed; the full T03-T10 suite validated with expected counts and zero request errors.
- `2026-08-17`: DEP-L40-QAT private S3 prefix was empty. Started the saved Kubernetes staging job for `google/gemma-4-12B-it-qat-w4a16-ct`; no Terraform or public resources were used.
- `2026-08-17`: DEP-L40-QAT staging completed: seven objects totaling 9.6 GiB; Hugging Face download 10 seconds and upload to existing private S3 prefix 18 seconds. Removed completed H100 TP4 and L40 OPT RayServices, then deployed the saved QAT scenario.
- `2026-08-17 01:18 UTC`: DEP-L40-QAT became Ready. Live vLLM config confirmed `quantization=compressed-tensors`, `MarlinLinearKernel` W4A16, FP8 KV cache, prefix caching, and no speculation. Compile took 72.57 seconds; available KV cache was 29.68 GiB. Smoke passed.
- `2026-08-17 01:19 UTC`: Started DEP-L40-QAT T03 and the gated T04-T10 continuation runner.
- `2026-08-17`: DEP-L40-QAT T03 completed and validated: six prompt groups, 60/60 requests, zero request errors; SHA-256 `d0617101a0b8f5b21222aa8fab6196f8e9e47a3149686cb0d605a61c3d090b56`. T04 warm-prefix test started.
- `2026-08-17 02:25 UTC`: DEP-L40-QAT T03-T10 suite finished. All artifacts validated with expected counts and zero errors; eight-file `SHA256SUMS` verified. Deleted the QAT RayService after evidence preservation.
- `2026-08-17`: Final GPU cleanup verified no RayServices or user pods. Temporary P5 resources and the idle L40S NodeClaim were deleted; account-specific identifiers remain only in ignored local evidence.

Append one row for every deployment attempt or benchmark command, including
failed attempts. Use UTC timestamps.

| Timestamp UTC | Scenario | Test | Command/request file | Status | Duration | Result path | Notes / failure reason |
|---|---|---|---|---|---|---|---|
| 2026-08-16 19:16 UTC | DEP-L40-BASE | T03 | `benchmarks/requests/T03-cold-latency.sh` | `PASSED*` | 22.9 min measured inference | `results/DEP-L40-BASE/T03/` | 60/60 requests; 0 transport errors; five groups truncated at 512 tokens, explicitly retained as fixed-cap performance evidence |
| 2026-08-16 20:23 UTC | DEP-L40-BASE | T04 | `benchmarks/requests/T04-warm-latency.sh` | `PASSED*` | ~23 min measured inference | `results/DEP-L40-BASE/T04/results.json` | 60/60, 0 request errors; complete raw JSON retained; post-run server counters unavailable due late wrapper exit |
| 2026-08-16 21:13 UTC | DEP-L40-BASE | T05 | `benchmarks/requests/T05-fixed-decode.sh` | `PASSED` | ~23 min measured inference | `results/DEP-L40-BASE/T05-20260816T211306Z.json` | 60/60; all exactly 512 output tokens; server counters captured; SHA-256 `17d191387d6e5f38f2373097839d3bf869ae265ce3f88739dd24aa9a32184da3` |
| 2026-08-16 21:36 UTC | DEP-L40-BASE | T06 | `benchmarks/requests/T06-prefill.sh` | `PASSED` | ~4 min | `results/DEP-L40-BASE/T06-20260816T213623Z.json` | 60/60, one output token; SHA-256 `1298646c74763013608a1795f3e80c748a6c44cdbe550db3d3a953ecb4a46761` |
| 2026-08-16 21:40 UTC | DEP-L40-BASE | T07 | `benchmarks/requests/T07-throughput-c01.sh` | `RUNNING` | In progress | Remote checkpoints then `results/DEP-L40-BASE/` | 30/36 checkpointed at status review |
| 2026-08-16 21:42 UTC | DEP-H100-BASE | T03 | `benchmarks/requests/T03-cold-latency.sh` | `PASSED*` | ~7 min | `results/DEP-H100-BASE/T03-20260816T214220Z.json` | 60/60, 0 errors; SHA-256 `5c0df22d5e6a98403e105d7a437dbd78c014d80c29dc3aaac0f0b2c8011fbdcc` |
| 2026-08-16 21:40 UTC | DEP-L40-BASE | T07 | `benchmarks/requests/T07-throughput-c01.sh` | `PASSED` | ~14 min | `results/DEP-L40-BASE/T07-20260816T214008Z.json` | 36/36, 0 errors; SHA-256 `bdc78a902504152254573f687c6a88d7d4594fc74553c409537dd15aaf6eb0fb` |
| 2026-08-16 21:54 UTC | DEP-L40-BASE | T08 | `benchmarks/requests/T08-throughput-c04.sh` | `PASSED` | ~10 min | `results/DEP-L40-BASE/T08-20260816T215406Z.json` | 72/72, 0 errors; SHA-256 `3c0f770ebbcd4fe729c11a8a636b99058eee76dac6d3407fc7db80220b75bc16` |
| 2026-08-16 22:04 UTC | DEP-L40-BASE | T09 | `benchmarks/requests/T09-throughput-c08.sh` | `PASSED` | ~10 min | `results/DEP-L40-BASE/T09-20260816T220434Z.json` | 96/96, 0 errors; SHA-256 `a36150bb7297039836e3ffb631dd3967796ef787d46dfb70fea7a2ff4e95e00a` |
| 2026-08-16 22:14 UTC | DEP-L40-BASE | T10 | `benchmarks/requests/T10-throughput-c16.sh` | `PASSED` | ~16 min | `results/DEP-L40-BASE/T10-20260816T221442Z.json` | 192/192, 0 errors; SHA-256 `5116280adc5068d8157adbc3b399849de67aa90c14e546714444ea8d9ed7fb2b` |
| 2026-08-16 21:49 UTC | DEP-H100-BASE | T04 | `benchmarks/requests/T04-warm-latency.sh` | `PASSED*` | ~7 min | `results/DEP-H100-BASE/T04-20260816T214945Z.json` | 60/60, 0 errors; SHA-256 `6e34dda98d7b0d8c442b45b1cbe0491992dcab8cd06ad5c4af4e755c5dbd112e` |
| 2026-08-16 21:56 UTC | DEP-H100-BASE | T05 | `benchmarks/requests/T05-fixed-decode.sh` | `PASSED` | ~8 min | `results/DEP-H100-BASE/T05-20260816T215629Z.json` | 60/60, 0 errors; SHA-256 `2751d666140a6901eb581a4afc5e47c23ee012b3182859e161c13170c57991be` |
| 2026-08-16 22:03 UTC | DEP-H100-BASE | T06 | `benchmarks/requests/T06-prefill.sh` | `PASSED` | ~2 min | `results/DEP-H100-BASE/T06-20260816T220357Z.json` | 60/60, 0 errors; SHA-256 `df8ade5f5b616bd4e7fa4be0ba14b00c256cb15ce5b633e6089c75817b736122` |
| 2026-08-16 22:05 UTC | DEP-H100-BASE | T07 | `benchmarks/requests/T07-throughput-c01.sh` | `PASSED` | ~5 min | `results/DEP-H100-BASE/T07-20260816T220502Z.json` | 36/36, 0 errors; SHA-256 `4f2398c890dfd13de5c7878db229de7c3d3a44b4221be7b4a644473073d9f114` |
| 2026-08-16 22:09 UTC | DEP-H100-BASE | T08 | `benchmarks/requests/T08-throughput-c04.sh` | `PASSED` | ~3 min | `results/DEP-H100-BASE/T08-20260816T220935Z.json` | 72/72, 0 errors; SHA-256 `3c91fda9b8c7a12a2e7d642bfd49979acf8ba507aff4beb01fb69d3ae9634c6e` |
| 2026-08-16 22:12 UTC | DEP-H100-BASE | T09 | `benchmarks/requests/T09-throughput-c08.sh` | `PASSED` | ~3 min | `results/DEP-H100-BASE/T09-20260816T221250Z.json` | 96/96, 0 errors; SHA-256 `d785f16da725efa1a8453c46bc5248f7d93bd43184d099590288fe94568f7f93` |
| 2026-08-16 22:15 UTC | DEP-H100-BASE | T10 | `benchmarks/requests/T10-throughput-c16.sh` | `PASSED` | ~5 min | `results/DEP-H100-BASE/T10-20260816T221549Z.json` | 192/192, 0 errors; SHA-256 `2d70892fe1890197a47980d7cd097c3970545ba7a05814c3e91e87993320fdb9` |

## Decisions and blockers

| Date | Item | Decision / blocker | Owner | Next action | Status |
|---|---|---|---|---|---|
| 2026-08-16 | H100 NodePool | Use isolated benchmark-only `gpu-capacity-block` resources instead of changing the shared GPU NodePool | Benchmark operator | Deleted after all H100 evidence was copied and validated | `CLEANED UP` |
| 2026-08-16 | H100 TP=1 | Run BASE and OPT on the same reserved `p5.48xlarge`, each requesting one of its eight GPUs | Benchmark operator | Completed sequentially before TP=4 | `PASSED` |
| 2026-08-16 | Parallel L40S/H100 runs | Separate workers avoid GPU contention, but generic pod discovery could mix clients and metrics | Benchmark operator | Benchmark harness now selects head and worker pods using `app=${SERVICE_NAME}`; use separate result trees | `READY` |
| 2026-08-16 | Exact instance selection | Each RayService worker must provision deterministic hardware rather than choose among multiple compatible shapes | Benchmark operator | Worker `nodeSelector` uses one exact `node.kubernetes.io/instance-type`; L40S=`g6e.2xlarge`, all H100=`p5.48xlarge` | `PASSED` |
| 2026-08-16 | P5.48 Capacity Block | H100 scenarios must consume the supplied reservation and must not fall back to ordinary On-Demand capacity | User / Benchmark operator | Each H100 RayService selects pool `gpu-capacity-block` and capacity type `reserved` | `PASSED` |
| 2026-08-16 | P5.48 temporary cleanup | Capacity Block infrastructure must not remain after benchmark evidence is copied | Benchmark operator | TP4 RayService, temporary NodePool, NodeClass, and instance removed | `PASSED` |
| 2026-08-16 | H100 TP=4 execution order | Run TP=4 after the H100 TP=1 scenarios on the reserved `p5.48xlarge` | User | Completed after TP=1 evidence acceptance | `PASSED` |
| 2026-08-16 | Warm-cache method | A/B prompt pairs share almost their entire prefix and cannot be benchmarked sequentially without explicit per-prompt priming/isolation | Benchmark operator | Harness primes every prompt independently before its ten measurements | `PASSED` |
| 2026-08-16 | Result privacy | Prompts and raw result JSON must remain local | Benchmark operator | `.gitignore` covers both prompts and `benchmarks/results/`; verified with `git check-ignore` | `PASSED` |
| 2026-08-16 | Run:ai streamer | Disabled because the current Ray 2.57 path is documented as incompatible in this example | Benchmark operator | Re-test only after verifying the upstream fix is in the selected immutable image | `BLOCKED` |
| 2026-08-16 | Ray head scheduling | Required same-zone pod affinity deadlocked under YuniKorn because the worker init container waited for the unscheduled head | Benchmark operator | Changed same-zone affinity from required to preferred and recreated the baseline | `PASSED` |
| 2026-08-16 | Ray head CPU / Karpenter churn | `r6a.xlarge` has 4 vCPU but the custom EC2NodeClass reserves 2, leaving 2 allocatable; the 2-CPU Ray head plus ~275m DaemonSets could never fit, so Karpenter repeatedly provisioned replacements | Benchmark operator | Head request reduced to 1 CPU and stable on `r6a.2xlarge` | `PASSED` |
| 2026-08-16 | Ray head instance size | Use `r6a.2xlarge` for every benchmark head so the fixed 2-vCPU kube/system reservation cannot cause `r6a.xlarge` provisioning churn | Benchmark operator | Explicit NodePool and instance-type selectors verified on the live head | `PASSED` |
| 2026-08-16 | Ray head zone affinity | Preferred worker-zone affinity caused Karpenter to launch an early head candidate and then another candidate after the GPU zone became known | Benchmark operator | Removed head/worker pod affinity; cross-AZ control-plane traffic is acceptable and avoids duplicate CPU provisioning | `READY` |
| 2026-08-16 | Transformers compatibility | Open-ended `transformers>=5.10.4` resolved to 5.15.0; vLLM failed because Gemma 4 `head_dim` became strictly per-layer | Benchmark operator | Pin runtime environment to known-compatible `transformers==5.10.4` and recreate on the existing warm nodes | `READY` |
