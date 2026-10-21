# agentgateway + Ray Serve demo — Phase 0 plan

Status: **approved 2026-10-20** with all six recommended answers; existing PoC RayServices stay. Phases 1, 3, 4 done and verified (Phase 2 replaced per decision 6). See NOTES.md for findings and deviations.
Date: 2026-10-20 · us-west-2 · cluster `ray-on-eks`

---

## 1. What exists today

| Area | Found | Impact on demo |
|---|---|---|
| Cluster | `ray-on-eks`, EKS **1.34** | `trafficDistribution: PreferClose` supported |
| Subnets | Pod/node subnets only in **us-west-2a/b/c** (`*-private-secondary1-*`, 100.64–66.0.0/16). No 2d subnets | GPU AZs must be in a/b/c |
| Node SG | the node security group (`ray-on-eks-node-*`), cluster security group | Valkey SG ingress source |
| KubeRay | operator **v1.7.1**; RayService has `gcsFaultToleranceOptions` (backend `redis`/`rocksdb`, `redisAddress`, `redisPassword`, `externalStorageNamespace`), `serveService` (with `trafficDistribution`), `excludeHeadPodFromServeSvc` | All GCS-FT + AZ-aware Service needs are met, no operator change |
| Existing Ray | ns `raydata`: RayServices `gemma4-g7-qat`, `gemma4-g7-qat-kv`, `e5-g7` (an earlier g7 benchmark PoC) on **3× g7.2xlarge spot** (2a, 2a, 2c), plus `heliostat-shared` RayCluster | Untouched. They use **24 of the 64-vCPU spot G quota** (see Q4) |
| Karpenter | **1.9.0**; NodePools incl. `gpu` (g5/g6/g6e/g7/g7e, OD+spot); EC2NodeClass **`gpu`** = AL2023 NVIDIA, 200 GiB gp3 600 MB/s, RAID0 NVMe, **SOCI parallel pull (`FastImagePull`) already on** | Reuse `gpu` and `default` NodeClasses; only add NodePools |
| GPU stack | NVIDIA GPU Operator (device plugin, DCGM exporter, GFD) | GPU metrics per node already exported |
| Gateway API | **No CRDs installed** | Must install v1.6.0 standard (cluster-wide, see Q5) |
| AWS LB Controller | **v2.8.1**, `--ingress-class=alb`, no Gateway API support | Installing Gateway API CRDs cannot trigger it |
| Existing LoadBalancer | `ingress-nginx-controller` (pre-existing, 103d) | Baseline for "nothing new" LB check; not touched |
| Metrics | kube-prometheus-stack in `monitoring` (Prometheus v3.10, Grafana). Selects **all** ServiceMonitors/PodMonitors in all namespaces, 30d retention | No new Prometheus; just add monitors + dashboards |
| Traces | ADOT collector `adot-collector.adot-collector:4317/4318`, pipeline OTLP → **AWS X-Ray**; OTLP metrics → AMP | Gateway traces go to X-Ray; no Jaeger/Tempo needed |
| Logs | aws-for-fluentbit + event-collector fluent-bit | Access logs to stdout as required |
| Identity | EKS **Pod Identity** agent; pattern = `module.team_pod_identity` | Use Pod Identity for `agw-demo` SAs |
| S3 | Existing bucket `ray-on-eks-spark-logs-*` already holds `models/gemma-4-12b-it`, `models/gemma-4-12b-it-qat-w4a16-ct`, `models/e5-large-v2`. S3 **Interface** endpoint with private DNS exists | No new VPC endpoint needed |
| ECR | `ray-llm:2.57.0.6c4022-py312-cu130` (11.7 GB), proven on g7 Blackwell in this cluster | Reusable as-is |
| Kyverno | Only policy mutates RayClusters in `raydata` ns | `agw-demo` ns unaffected |
| ElastiCache | None | New |

## 2. GPU spot availability (us-west-2)

Offered in a/b/c/d: g7e.*, g7.*, g6e.*; g5.* in a/b/c.

Spot placement scores (1–10, single-AZ, target 2):

| Type | usw2-az2 (2a) | usw2-az1 (2b) | usw2-az3 (2c) | Region |
|---|---|---|---|---|
| **g7e.2xlarge / 4xlarge** | 1 | 1 | 1 | 3 |
| g5.xlarge / 2xlarge | 1 | 1 | 1 | 1 |
| g6.xlarge / 2xlarge, g6e.xlarge | 1 | 1 | 1 | — |
| **g7.2xlarge** | **9** | **9** | **9** | — |

Current spot prices ($/h): g7.2xlarge 1.18 (2a) / 1.27 (2b,2c); g7e.2xlarge 1.94 (2a) / 1.91 (2b) / 3.10 (2c); g5.xlarge ~0.53; g5.2xlarge ~0.41–0.47.

Spot quota "All G and VT Spot" = **64 vCPU**; 24 in use by the PoC nodes.

**Result: g7e (and g5) spot scores are poor.** Per the prompt, this needs your decision (Q1). Recommendation below.

## 3. Version and compatibility checks

| Item | Finding | Decision |
|---|---|---|
| agentgateway OSS | Latest stable **v1.6.0** (2026-10-02). Charts `oci://cr.agentgateway.dev/charts/agentgateway-crds` + `.../agentgateway` 1.6.0 | Use 1.6.0 |
| agentgateway CRDs | `AgentgatewayParameters`, `AgentgatewayPolicy`, `AgentgatewayBackend`, `AgentgatewayModel` (inspected from chart schema) | — |
| Gateway API | Docs require v1.6.0 (standard channel has `GRPCRoute`) | Install v1.6.0 standard |
| Proxy Service type | Generated proxy Service defaults to LoadBalancer; `AgentgatewayParameters.spec.service.spec` overrides it; `spec.deployment.spec` sets replicas/spread; `spec.podDisruptionBudget` | Parameters created **before** the Gateway with `type: ClusterIP` |
| Routing by model | `AgentgatewayModel` (`match.model`, `provider: Custom`, `custom.backendRef` → Service, `formats: Completions/Embeddings`) | Route `gemma-12b` → `gemma-12b-serve-svc:8000` |
| API keys → team | Secret/ConfigMap entries `{"keyHash": "sha256:…", "metadata": {"team": "…"}}`, readable as `apiKey.team` in CEL | Hashed keys in a ConfigMap; raw keys never stored |
| Rate limits | `traffic.rateLimit.local[]`: `requests` or `tokens`, `unit`, `burst`, `key` (CEL, e.g. `apiKey.team`), plus `conditional[]` for per-team limits | Local, per pod (as requested) |
| Cost | Native **model cost catalog** (ConfigMap via Gateway-level `AgentgatewayParameters.modelCatalog`) → `llm.cost.total` in CEL, `agw.ai.usage.cost.total` in access logs, metric `agentgateway_cost_catalog_lookups_total` | Internal $/1M token price in catalog |
| Metrics per team | `frontend.metrics.attributes.add` with `apiKey.team` → label on `agentgateway_gen_ai_client_token_usage` | Teams dashboard straight from Prometheus |
| Tracing | `frontend.tracing` → OTLP gRPC | ADOT → X-Ray |
| **Global** limits | OSS **does** support global request/token limits through an external Envoy-compatible rate-limit service + Redis (`rateLimit.global`) | Prompt said Enterprise-only; it isn't. Demo stays on local limits (fewer components); DEMO.md will say global is available in OSS for one extra service |
| Ray / vLLM image | Proven: `ray-llm:2.57.0.6c4022-py312-cu130` (CUDA 13, Blackwell OK on g7). Newer upstream: `2.58.1-py312-cu130` (published 2026-10-21) | Reuse 2.57.0 (proven here); 2.58.1 optional |
| `runai_streamer` | **ray-project/ray#64978 still open**: with `s3://` `model_source` it crashes on 2.57 (we hit it in the Gemma 4 work) | Use Ray Serve LLM's built-in S3 download (measured before). Will retest on 2.58.1 and switch only if fixed |
| PrefixCacheAffinityRouter | In Ray ≥ 2.49 (`ray.serve.llm.request_router.PrefixCacheAffinityRouter`) | Use; will confirm the import path in the image |
| Ray Serve gRPC ingress | `grpc_options` (`port`, `grpc_servicer_functions`) in serveConfigV2; the proxy imports servicer modules at startup, so they must be on `PYTHONPATH` on every node | Mount generated `*_pb2*.py` from a ConfigMap (no custom image needed) |
| gRPC metering at gateway | Can't confirm from docs whether access-log CEL sees **response trailers**. | Test both paths in Phase 4: trailer/header `x-usage-prompt-tokens`, with the fallback (`x-team-id` header + `embed_tokens_total{team}`) |

## 4. Proposed design (changes vs. the prompt are marked ⚑)

**GPU AZs: us-west-2a (usw2-az2) and us-west-2b (usw2-az1)**: both score 9 for g7.2xlarge, and they're the two cheapest.

| Component | Spec | Where |
|---|---|---|
| NodePool `agw-demo-cpu` | on-demand, amd64, m7i/m7a/m6i large–2xlarge, a/b/c, NodeClass `default`, limit 48 vCPU, `WhenEmpty` 10m | Ray heads, gateway proxies, clients |
| NodePool `agw-demo-gpu-gemma` ⚑ | **spot only**, `g7.2xlarge` (RTX PRO 4500 32 GB) + `g7e.2xlarge` allowed for diversity, AZs 2a/2b, NodeClass `gpu`, taints `nvidia.com/gpu` + `agw-demo=true`, limit 2 GPU, `WhenEmpty` 30m | Gemma workers |
| NodePool `agw-demo-gpu-embed` ⚑ | **spot only**, `g5.xlarge`, `g5.2xlarge`, `g6.xlarge`, `g6.2xlarge`, `g7.2xlarge` (Karpenter takes the cheapest available), AZs 2a/2b, same taints, limit 2 GPU | Embedding workers |
| RayService `gemma-12b` ⚑ | **Gemma 4 12B-it QAT w4a16** (already in S3; 66 tok/s decode on g7.2xlarge measured), served as `gemma-12b`; 2 workers, zone spread `DoNotSchedule`; head on `agw-demo-cpu`, `num-cpus: 0`; GCS FT → Valkey ns `gemma-12b`; `max_num_seqs 64`, `max_ongoing_requests 64`, `max_queued_requests 16`, PrefixCacheAffinityRouter; `serveService` with `trafficDistribution: PreferClose`, `excludeHeadPodFromServeSvc: true` | ns `agw-demo` |
| RayService `embeddings` ⚑ | **Qwen3-Embedding-0.6B** (Apache-2.0, no token, vLLM pooling support, 32k context, real tokenizer for counts) on vLLM in a custom deployment exposing gRPC `embeddings.v1.EmbeddingService/Embed` on 9000 + HTTP `/v1/embeddings`; 2 workers spread; GCS FT ns `embeddings` | ns `agw-demo` |
| ElastiCache Valkey | `agw-demo-valkey`, cluster mode off, 1 primary + 1 replica (2a/2b), Multi-AZ auto-failover, `cache.t4g.small`, TLS + AUTH token (Ray supports `rediss://`; will verify on the image before relying on it), SG 6379 from node SG only | Terraform (deploy.sh) |
| IAM ⚑ | Pod Identity `agw-demo/agw-ray` → **read-only** `s3://…/models/*`; `agw-demo/agw-model-stager` → write `models/qwen3-embedding-0.6b/*` only | Terraform (deploy.sh) |
| S3 ⚑ | **Reuse the existing bucket's `models/` prefix** (Gemma 4 already there). Only Qwen3-Embedding is staged (CPU Job, ~1.2 GB) | — |
| Images ⚑ | **No custom image build**: reuse ECR `ray-llm:2.57.0…`; gRPC stubs come from a ConfigMap. The `gpu` NodeClass already uses SOCI parallel pull; we'll **measure pull time on a fresh node** (SOCI parallel vs. the default pull on the `default` class) | — |
| agentgateway ⚑ | Gateway API CRDs v1.6.0 + `agentgateway-crds` + `agentgateway` 1.6.0 via **ArgoCD**, following the repo pattern (`infra/terraform/agentgateway.tf`, `helm-values/`, `argocd-applications/`, `enable_agentgateway` default false, true in ray-on-eks tfvars) | ns `agentgateway-system` |
| Gateway | `agw-demo-gw`: listeners `http` 8080 (HTTPRoute + AgentgatewayModel) and `grpc` 9090; Parameters: 3 replicas, zone spread, PDB minAvailable 2, ClusterIP, model catalog, JSON logs | ns `agentgateway-system` |
| Observability | ServiceMonitor/PodMonitor for gateway + Ray/vLLM metrics into existing Prometheus; 4 Grafana dashboards (JSON in repo + ConfigMap sidecar); traces → ADOT → X-Ray | existing stack |

### Who applies what

| Via `deploy.sh` (you run it) | Via kubectl (I apply, from `examples/agw-demo/`) |
|---|---|
| 2 EC2NodeClasses + 3 NodePools (stack overlay `terraform/manifests/agw-demo/karpenter/`, gated by `enable_agw_demo`) | Namespace `agw-demo`, RayServices, model staging Job |
| ElastiCache Valkey + SG + K8s Secret, Pod Identity roles (stack overlay `terraform/agw-demo.tf`) | Gateway, Parameters, routes, models, policies, API-key ConfigMap |
| Gateway API CRDs + agentgateway via ArgoCD (base `infra/terraform/agentgateway.tf`, flag-gated) | ServiceMonitors, dashboards, demo Jobs |

### Rough hourly cost (new resources only)

| Item | $/h |
|---|---|
| 2× g7.2xlarge spot (Gemma) | ~2.45 |
| 2× g5.xlarge spot (embed; if it falls back to g7.2xlarge: ~2.45) | ~1.06 |
| agw-demo-cpu on-demand (~2× m7i.xlarge for heads + 3× m7i.large for proxies/clients) | ~0.70 |
| ElastiCache 2× cache.t4g.small | ~0.07 |
| **Total** | **~$4.3/h (~$103/day)**; up to ~$5.7/h with g7 fallback for embeddings |

Not counted: the 3 existing PoC g7 nodes (~$3.6/h) that are already running.

Spot quota: new 16 (Gemma) + 8 (embed, g5) = 24 vCPU, plus 24 existing = 48 of 64. With the g7 fallback for embeddings it's 56 of 64.

## 5. Decisions needed from you

1. **GPU type** ⚑: g7e/g5 spot scores are 1/10. Use **g7.2xlarge spot (score 9) for Gemma**, with g7e.2xlarge allowed too, and a diversified g5/g6/g7 list for embeddings?
2. **Models and bucket** ⚑: Use **Gemma 4 12B QAT** (already staged, no HF token, proven on g7) instead of gated Gemma 3 12B, plus Qwen3-Embedding-0.6B, all in the **existing bucket's `models/` prefix** rather than a new `agw-demo-models-*` bucket?
3. **Valkey**: ElastiCache (managed, Multi-AZ, ~$0.07/h, via Terraform in deploy.sh) as the prompt specifies? The cluster also has an in-cluster Valkey option (`enable_valkey`), but ElastiCache tells the "regional managed service" story better.
4. **Existing PoC RayServices** in `raydata` (3× g7.2xlarge spot, ~$3.6/h, 24 vCPU of spot quota): keep them running, or can I scale them down? I won't touch them unless you say so.
5. **Base infra change** (AGENTS.md "ask first"): add `infra/terraform/agentgateway.tf` + Gateway API CRDs as a reusable, flag-gated component (default off; on only in ray-on-eks)? The alternative is overlay-only in `data-stacks/ray-on-eks/terraform/`.
6. **SOCI**: skip building custom images and SOCI v2 indexes (parallel pull mode needs no index), and instead show measured pull time with SOCI parallel pull vs. the default pull?

## 6. Repository layout

```
data-stacks/ray-on-eks/
├── terraform/
│   ├── data-stack.tfvars                       # + enable_agentgateway, enable_agw_demo
│   ├── agw-demo.tf                             # ElastiCache, SG, Pod Identity, K8s Secret
│   └── manifests/karpenter/nodepool-agw-demo-{cpu,gpu-gemma,gpu-embed}.yaml
└── examples/agw-demo/
    ├── PLAN.md  NOTES.md  ARCHITECTURE.md  DEMO.md  cleanup.sh
    ├── infra/README.md      # points at the terraform overlay files above
    ├── proto/  ray/  gateway/  observability/  regions/  demo/
infra/terraform/
    ├── agentgateway.tf  helm-values/agentgateway.yaml  argocd-applications/{gateway-api-crds,agentgateway-crds,agentgateway}.yaml
```
