# NOTES — decisions, version checks, surprises

## 2026-10-20 — Phase 0

- Spot placement: g7e.2xlarge/4xlarge = 1 in every AZ (3 region-wide); g5/g6 = 1; g7.2xlarge = 9 in az1/az2/az3. us-east-1/2 give g7e a 9, but the demo is single-Region us-west-2.
- `get-spot-placement-scores` rejects a quoted multi-type string ("g7e.2xlarge g7e.4xlarge" as one arg). Pass the types as separate args.
- Spot G/VT quota is 64 vCPU; 24 are used by existing PoC nodes.
- No us-west-2d subnets in the VPC, so the GPU AZs must be in a/b/c even though 2d has the cheapest g7.
- KubeRay 1.7.1 `gcsFaultToleranceOptions.backend` takes `redis` or `rocksdb` (rocksdb is new). We use redis/Valkey.
- AWS LB Controller v2.8.1 has no Gateway API support, so Gateway API CRDs can't trigger an NLB/ALB.
- agentgateway 1.6.0 CRDs inspected offline from the chart (`helm pull`, nothing applied).
- The prompt says OSS global rate limits are Enterprise-only. They aren't: `rateLimit.global` with an Envoy ratelimit server + Redis is in OSS docs (virtual-keys guide). We still use local limits to keep the component count low.
- agentgateway has a native model cost catalog (`modelCatalog` on Gateway-level Parameters). Per-request USD shows up in logs, traces, CEL, and metrics.
- The CEL reference URL (`/docs/kubernetes/latest/reference/cel.md`) returns 404. Field names come from the guides (`apiKey.<field>`, `llm.cost`, `llm.requestModel`, `backend.endpoint`, `response.code`). Whether access-log CEL can see gRPC response trailers is unknown; we'll test in Phase 4.
- ray-project/ray#64978 (runai_streamer + s3:// model_source) is still open, so runai_streamer stays off.
- Kyverno history-collector policy is scoped to ns `raydata`; it won't touch `agw-demo`.
- Prometheus selects all ServiceMonitors/PodMonitors cluster-wide, so no label tricks are needed.

## 2026-10-20 — Phase 1 (code written; waiting on deploy.sh)

- **Change vs PLAN:** NodePools are not in `terraform/manifests/karpenter/`. That folder is applied unconditionally and Karpenter can only set EC2 tags on an EC2NodeClass. They live in `terraform/manifests/agw-demo/karpenter/` with their own NodeClasses `agw-demo-cpu`/`agw-demo-gpu` (copies of `default`/`gpu` plus `project=agw-demo, owner=vara` tags). All of it is gated by `enable_agw_demo`.
- **Change vs prompt:** no extra `NoSchedule` demo taint on GPU nodes. Every GPU Operator DaemonSet (device plugin, DCGM, GFD, validator) tolerates only `nvidia.com/gpu`, so any other NoSchedule taint would leave the node with 0 allocatable GPUs. GPU pools use `nvidia.com/gpu=true:NoSchedule` + `agw-demo=true:PreferNoSchedule`. The CPU pool uses only the soft taint, because aws-for-fluentbit has no tolerations. Our pods pin themselves with `nodeSelector: agw-demo/pool`.
- Valkey: engine 8.2 (`default.valkey8`), `cache.t4g.small` ×2, Multi-AZ, TLS + AUTH. Address is stored as `rediss://…:6379` in Secret `agw-demo/agw-demo-valkey` (keys `address`, `password`). Whether Ray 2.57 accepts `rediss://` gets verified in Phase 3.
- IAM roles: `agw-demo-ray` (read `models/*`) → SA `agw-demo/agw-ray`; `agw-demo-model-stager` (write `models/qwen3-embedding-0.6b/*`) → SA `agw-demo/agw-model-stager`.
- agentgateway via ArgoCD from OCI `cr.agentgateway.dev/charts`. Needed a repo Secret with `enableOCI` (same pattern as `quay-io`). Gateway API CRDs come from git `config/crd/standard@v1.6.0` with `prune: false`.
- Validation without terraform: rendered every template and ran `kubectl apply --dry-run=server`. All Karpenter objects, ArgoCD Applications and the repo Secret were accepted. Checked module inputs/outputs against the cached module sources.
- LoadBalancer baseline before deploy: only `ingress-nginx/ingress-nginx-controller`.

## 2026-10-20 — deploy.sh run 1 failed (not demo code)

- `init -upgrade` pulled terraform-aws-modules/s3-bucket **5.17.0**, which adds `count` to the module's data sources. Terraform treats that as implicit moves in state, and the first `-target=module.vpc` apply refused with "Moved resource instances excluded by targeting". Nothing was applied.
- Fix (approved): pinned s3-bucket to `~> 5.0, < 5.17.0` in base `storage.tf` (×2), `trino.tf` (×2), `airflow.tf`, `starrocks.tf`, `polaris.tf`. Lift it once the repo does one untargeted apply on 5.17.

## 2026-10-21 — Phase 1 verified, Phase 3 up (all times UTC)

Phase 1 (after deploy.sh): ArgoCD `gateway-api-crds`, `agentgateway-crds`, `agentgateway` all Synced/Healthy; GatewayClass `agentgateway` Accepted; 14 Gateway API + agentgateway CRDs; NodePools/NodeClasses Ready; Valkey `available` (001 primary in 2a, 002 replica in 2b, Multi-AZ, TLS, AUTH); Pod Identity associations for `agw-ray` and `agw-model-stager`; no new LoadBalancer.

Image checks (ray-llm 2.57.0.6c4022, vLLM 0.25.1):
- Router class path: `ray.serve.llm.request_router:PrefixCacheAffinityRouter`. A `KVAwareRouter` also ships.
- `grpc_tools` isn't in the image. Stubs are generated locally with grpcio-tools 1.76.0 (gencode protobuf 6.31.1, runtime 6.33.6, which is compatible) and committed under `proto/gen/`.
- `RayServegRPCContext` has `set_trailing_metadata` but no initial-metadata setter. Token count goes in the `x-usage-prompt-tokens` trailer plus the response body.
- boto3 1.29.7 / botocore 1.32.7 are too old for EKS Pod Identity credentials. The embed app downloads with `pyarrow.fs.S3FileSystem`, as Ray Serve LLM does.
- `rediss://` works: GCS log shows `StorageType::REDIS_PERSIST` against the ElastiCache primary, and the head starts fine with TLS + AUTH.

Measured:
| What | Value |
|---|---|
| Qwen3-Embedding-0.6B staging (HF → S3, 1.1 GiB) | S3 upload 7 s; Job ~80 s incl. pip |
| ray-llm image pull (11.7 GB), m6a.xlarge, gp3 600 MB/s, SOCI parallel | 1m38s |
| ray-llm image pull, g7.2xlarge, NVMe RAID0, SOCI parallel | 59–61 s (4 nodes) |
| gemma-12b apply → Ready (cold GPU nodes) | ~6m20s |
| Gemma weights load (after S3 download) | 2.89 s |
| Gemma KV cache (fp8, 0.90 util, g7.2xlarge 32 GB) | 197,609 tokens; 12.06× concurrency at 16k |
| Qwen3 S3 download (pyarrow copy_files) / GPU load | 48.8 s / 3.7 s. The download is slow for 1.1 GB; could parallelise later |

Placement: gemma workers g7.2xlarge spot in 2a + 2b; embed workers landed on **g7.2xlarge** spot in 2a + 2b (Karpenter chose g7 over g5/g6); heads on agw-demo-cpu on-demand (m6a.xlarge 2c, m6a.large 2b).

Surprises:
- **KubeRay 1.7.1 drops extra ports from `serveService`** and keeps only the HTTP serve port. gRPC is reached through companion Service `embeddings-grpc-svc:9000` (h2c, PreferClose, selector `app=embeddings, ray.io/serve=true`). `ray.io/serve` is readiness-managed by KubeRay.
- gRPC with a single Serve app needs **no `application` metadata**. Add `-H 'application: embeddings'` only if more apps get deployed to that cluster.
- Ray custom metrics are exported with a `ray_` prefix: `ray_embed_tokens_total{team,protocol,model}`.

Verified: `/v1/models` → `gemma-12b`; chat 200 with usage; streaming with `include_usage` emits a final usage chunk; gRPC Embed → 2×1024 vectors, `promptTokens` 12, trailer `x-usage-prompt-tokens: 12`; HTTP `/v1/embeddings` 200 + `x-usage-prompt-tokens` header.

Cleanup requested by user: deleted the PoC RayServices `raydata/{gemma4-g7-qat, gemma4-g7-qat-kv, e5-g7}`. Their 3 g7.2xlarge spot nodes (pool `gpu`) are left to Karpenter consolidation. `heliostat-shared` kept.

## 2026-10-21 — Phase 4: agentgateway configured and verified

Applied with `gateway/deploy.sh`: Gateway `agentgateway-system/agw-demo-gw` (listeners `http` :8080, `grpc` :9090), Service **ClusterIP**, 3 proxies, one per AZ (2a/2b/2c), PDB minAvailable 2, JSON logs, cost catalog. AgentgatewayModels `gemma-12b`, `qwen3-embedding-0.6b`; GRPCRoute `embeddings-grpc` (+ ReferenceGrant in agw-demo); policies `agw-demo-llm` (listener http), `agw-demo-grpc` (GRPCRoute), `agw-demo-telemetry` (Gateway), all Accepted/Attached. LoadBalancer check: only the pre-existing ingress-nginx.

Verified:
- No key → 401 (`no API Key found`); wrong key → 401 (`invalid credentials`); gRPC without key → `Unauthenticated`. Each team key → 200.
- `/v1/models` is served by the gateway from attached models; unknown model → 404 `model_not_found`.
- Routing by model name: `gemma-12b` → gemma svc, `qwen3-embedding-0.6b` → embeddings svc (HTTP `/v1/embeddings`).
- gRPC Embed through gateway: vectors + `x-ratelimit-*` headers + trailer passed through.
- Per-team limits (per pod): team-labs got 429 on the **token** bucket after 6×530 tokens (`x-ratelimit-limit: 3000`, `Retry-After: 6`), then on the request bucket (10/min). team-search, sent right after, got 200 in 0.37 s.
- max_tokens cap: team-labs `max_tokens: 8000` → 512, `finish_reason: length`. Client values below the cap are honoured (40 → 40) for both `max_tokens` and `max_completion_tokens`.
- Streams get usage without the client asking (stream_options.include_usage injected); access log has `agw.ai.time_to_first_token` and `agw.ai.time_per_output_token`.
- Access log (JSON) per LLM request: team, tier, gen_ai.request/response.model, input/output tokens, `agw.ai.usage.cost.total` (matches catalog math), endpoint, trace.id, duration.
- Traces: gateway spans visible in **AWS X-Ray** via ADOT (2 segments per request).

Findings / changes:
- **Proxy spread needed `minDomains: 3` + `matchLabelKeys: [pod-template-hash]`.** Without minDomains the scheduler only counts zones that already have demo CPU nodes (it put 2 in 2c). Without matchLabelKeys a rolling update counts the outgoing pods.
- **max_tokens cap bug, fixed:** this OpenAI-compatible path passes `max_tokens` through unchanged, and vLLM prefers `max_completion_tokens`, so my first expression raised small requests up to the team cap. The expression now reads either field.
- `traffic.timeouts` only applies to HTTPRoute targets (CRD doc), so it isn't used on the model listener. Ray Serve's `request_timeout_s` (300 s Gemma / 30 s embeddings) bounds requests.
- **gRPC token metering: the fallback path is used.** Access-log CEL in 1.6.0 doesn't see response trailers (`response.trailers[...]` and `response.headers["x-usage-prompt-tokens"]` both absent on gRPC lines), and Ray Serve can't set initial metadata. The gateway sets trusted `x-team-id` from the API key (and strips `authorization`); the service counts `ray_embed_tokens_total{team,protocol,model}`. Verified the counter shows gateway-injected teams. gRPC log lines still carry team/tier and the upstream **pod IP** (`endpoint`).
- For HTTP embeddings, the backend's `x-usage-prompt-tokens` response header *is* readable in access-log CEL.
- `llm.params.max_tokens` logs the client-requested value, not the capped one.
- Cost catalog: provider id for `provider: OpenAI` + custom baseURL is `openai`; lookups priced `Exact`.

Old PoC g7 nodes: all 3 drained and terminating by 05:21 (Underutilized consolidation, 10% budget).

## 2026-10-21 — Phase 5: observability, plus a router incident found by load testing

Observability (no new components):
- agentgateway chart already created a PodMonitor/ServiceMonitor; Prometheus scrapes all 3 proxies + controller.
- Native gateway metrics carry `team` (from `frontend.metrics.attributes: team=apiKey.team`): `agentgateway_gen_ai_client_cost_usd_total` (**USD per team/model, priced by our catalog**), `agentgateway_gen_ai_client_token_usage_*`, `agentgateway_requests_total{status}`, TTFT/TPOT histograms, `agentgateway_request_duration_seconds`, `agentgateway_cost_catalog_lookups_total`.
- Added `observability/podmonitor-ray.yaml` for Ray pods (port `metrics`): `ray_embed_tokens_total{team}`, `ray_serve_*`, `ray_vllm_*`.
- Dashboard `agw-demo · Tenant chargeback & SLOs` (uid `agw-demo-tenants`), generated by `observability/build_dashboard.py`, loaded via ConfigMap label `grafana_dashboard=1` (`observability/deploy.sh`). Team dropdown (All / per team). Every panel query was validated against Prometheus.
- `ray_vllm_kv_cache_usage_perc` is exported intermittently, so the panel uses `max_over_time(...[2m])`.
- Grafana admin creds: Secret `monitoring/grafana-admin-secret`.

**Incident (load test, 22:41–22:47 local):** the first mixed run (3 Jobs × profile = ~9 chat rps, above Gemma capacity) got **0 successful chats**: ReadTimeouts (>120 s), 500s, 503s. Embeddings were unaffected.
- The LLMServer replicas were fine (calls OK in 1–2 s) but got **no calls 22:43–22:47**.
- Ray LLM's `OpenAiIngress` router ran as **1 replica** (default) on a GPU worker. It stopped forwarding, failed its health check, and was force-killed. The replacement on the same worker sat at 3.6 cores and **12+ GiB RSS, still growing (~7 MB/s) with no traffic**, logging "Failed to get queue length from Replica ... within 0.1s" and cancelling already-finished requests.
- Fix (serveConfigV2, applied in place): `ingress_deployment_config` with 2 replicas (`min/max_replicas: 2`, `max_replicas_per_node: 1`, `num_cpus: 1`), and **removed `PrefixCacheAffinityRouter`** (default power-of-two). Both were changed together for stability, so the leak isn't attributed definitively. Prime suspect: the prefix router's state inside the ingress handle under cancellations. The change also restarted one LLMServer replica.
- After the fix: router RSS flat at ~1,044 MiB through a 5-min mixed run and a 2× overload run; 0 timeouts.
- Loadgen `mixed` rates are now per Job and sized for capacity (3 Jobs ≈ 2.3 chat rps + 6 gRPC rps + 1.5 HTTP embed rps). Half the chats stream.

Measured (mixed, 5 min, 3 AZs): TTFT p50/p95/p99 50/60/80 ms; TPOT p50/p95 17.5/24 ms; chat (120 tok) p50/p95 1.81/1.85 s; gRPC embed p50/p95 29/35 ms; HTTP embed 34/45 ms; 0 errors. 10-min cost: search $0.032 (incl. gRPC $0.0006), support $0.029, labs $0.014.

Overload (`overload` profile, 39 rps, 60 s, team-search): 1,329×200 (p50/p95/p99 2.7/6.4/7.8 s), 883×429 (gateway per-team limit), 116×503 (Ray queue full), 0 timeouts; direct chat 0.30 s right after.

## 2026-10-21 — Phase 6/7: gateway overhead + availability drills (UTC)

Gateway overhead (`demo/loadgen/overhead.py`, interleaved A/B from one pod in 2a, no other load): chat max_tokens=1 direct p50/p99 27.4/28.9 ms vs gateway 29.6/32.8 → **+2.3 / +3.9 ms**; gRPC Embed 24.3/25.3 vs 25.6/26.6 → **+1.3 / +1.3 ms**. The gateway path includes 100% trace sampling and possibly one cross-AZ hop (gateway Service has no trafficDistribution).

Background traffic for drills: `steady` profile × 3 Jobs (2a/2b/2c), timeline every 5 s.
- **(a) Gateway proxy delete** 06:24:57 (pod in 2a): replacement Ready ~8 s; PDB allowed-disruptions 0 meanwhile. **0 failed / 438.**
- **(b) Gemma GPU node in 2a: cordon + drain** 06:25:58. The worker was evicted, the 2b replica carried all chat. **No replacement node for 10+ min**: Karpenter "all available instance types exceed limits for nodepool agw-demo-gpu-gemma", because the cordoned node still counted against `nvidia.com/gpu: 2`. Deleted the node at 06:36:49 (what a spot reclaim does); Karpenter launched a 2a node at once; Serve back to 2+2 at **+6m22s**. Client impact over 06:25:50–06:43:30: **4 failed of 1,232 chats** (1×503 + 3 stream RemoteProtocolError), all at 06:26:30 = the evicted worker's in-flight requests at the end of its 30 s grace period. 0 of 7,842 embedding requests failed.
  - Fix in code (applies on next deploy.sh): GPU NodePool limits → `nvidia.com/gpu: 3`, `cpu: 24` (N+1). Also needed for Karpenter drift/expiry replacement. Spot quota worst case 48/64 vCPU.
  - Improvement (not done): graceful Ray Serve drain on worker eviction (longer terminationGracePeriodSeconds + preStop).
- **(c) Gemma Ray head delete** 06:43:39: new head Running ~36 s; GCS `REDIS_PERSIST` from Valkey; Serve replicas `RECOVERING` → `RUNNING` (re-adopted, 0 worker restarts); reconciled **+78 s**. **0 failed / 1,207.**

New: `setup.sh` (idempotent build, tested on the live env: 1.5 min, no restarts, smoke 401/200/200), `cleanup.sh` (dry run by default; dry run only), `demo/drills.sh`. Staging Job skips when weights are already in S3. setup.sh smoke test reads the key from the Secret inside the pod.

## 2026-10-21 — Repo hygiene, remote state, defaults

- `enable_agw_demo` defaults to false in the ray-on-eks tfvars (the stack is shared); `enable_agentgateway = true` stays (agentgateway is part of the opinionated ray-on-eks stack). Base variable defaults stay false.
- Removed the `agw_demo_gpu_zones` variable. Demo GPU workers + Valkey use `slice(local.azs, 0, 2)` = first two AZs of the cluster region (us-west-2a/2b today, identical to before, so no Valkey replacement).
- Remote state (opt-in, no account number in the repo): `install.sh` writes `_local/backend.tf` for S3 when `TF_STATE_BUCKET` is set (key `<stack>/terraform.tfstate`, `use_lockfile` on Terraform ≥ 1.10) and runs `init -migrate-state`. `ray-on-eks/deploy.sh` sets `TF_STATE_BUCKET` only if `terraform-state-<account>-<region>` exists in the caller's account. Bucket created 2026-10-21 (private, versioned, AES256, TLS-only, noncurrent versions expire after 90 days). Local Terraform is 1.8.5, so there's no locking until upgraded.
- Public-repo scrub: removed the account id, VPC/SG ids and a customer name from PLAN.md. Raw PoC benchmark result JSONs (untracked, `gemma4-vllm-rayserve/benchmarks/results/*/T*.json` etc.) contain model responses naming a customer's products, so they must not be committed.
