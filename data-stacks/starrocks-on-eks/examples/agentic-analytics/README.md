# Agentic Analytics on StarRocks — EKS Prototype

An end-to-end example of an **agentic analytics loop** running entirely inside an existing EKS cluster.
A user posts one plain-English question; within ~25 seconds the agent returns a structured root-cause report
backed by real SQL against StarRocks.

---

## Architecture

```
┌──────────────────┐
│      User        │   "CTR dropped for advertiser_42 in last 15min"
│  CLI / curl      │
└────────┬─────────┘
         │ POST /investigate
         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                        EXISTING EKS CLUSTER                                │
│                                                                            │
│  ┌──────────────────┐   HTTP/JSON   ┌──────────────────┐   MySQL :9030   │
│  │ agent            │──tool calls──▶│   mcp-server     │──templated SQL──┐
│  │ (LangGraph)      │               │                  │                 │
│  │                  │               │  Tools:          │                 │
│  │ • Decompose      │               │  • list_dims     │                 │
│  │ • Execute        │               │  • query_metric  │                 │
│  │ • Analyze        │               │  • compare_base  │                 │
│  │ • Report         │               │                  │                 │
│  │ FastAPI :8080    │               │  FastAPI :8000   │                 │
│  └────────┬─────────┘               └──────────────────┘                 │
│           │                                                              ▼
│           │ bedrock:InvokeModel (3 calls)             ┌─────────────────────┐
│           │ via IRSA                                  │  StarRocks           │
│           │                                           │  Shared-Data mode    │
│           │                                           │  • FE x3             │
│           │                                           │  • CN autoscaled     │
│           │                                           │  • ad_events PK tbl  │
│           │                                           │  • async MV (1-min)  │
│           │                                           └──────────┬──────────┘
│           │                                                      │
│  ┌────────────────────┐                                          │ MySQL INSERT
│  │ seed-data (Job)    │──────── 1M synthetic events ────────────▶│
│  └────────────────────┘         (one injected anomaly)           ▼
│                                                          ┌──────────────┐
│  Observability: kubectl logs deploy/agent                │  S3 (primary │
│  (full plan + tool trace + report)                       │  storage)    │
└────────────────────────────────────────────────────────────────────────────┘
                            ▲
                            │ HTTPS
                ┌───────────┴────────────┐
                │   Amazon Bedrock       │
                │   Claude Sonnet 4.6    │
                │                        │
                │   Decompose → Analyze  │
                │   → Synthesize report  │
                └────────────────────────┘
```

### Request flow

1. `POST /investigate` hits the **agent** (port-forward for the prototype)
2. **Decompose** — Claude breaks the question into 4–6 dimension drill-downs → JSON plan
3. **Execute** — asyncio fans out concurrent HTTP calls to the **mcp-server** (one `list_dims` + one `compare_base` per plan item)
4. **MCP server** runs templated SELECT statements against StarRocks; the agent never sends raw SQL
5. **Analyze** — Claude identifies which dimension/value is the outlier
6. **Report** — Claude writes a markdown root-cause report → returned to the user
7. Total elapsed: ~20–30 s

---

## Components

| Component | Image | Port | ServiceAccount |
|-----------|-------|------|----------------|
| `agent` | `agentic-analytics/agent` | 8080 | `agent-sa` (Bedrock IRSA) |
| `mcp-server` | `agentic-analytics/mcp-server` | 8000 | `mcp-sa` |
| `seed-data` | `agentic-analytics/seed` | — | `mcp-sa` |

**MCP tools** (allow-listed dimensions and metrics — no prompt injection reaches StarRocks):

| Tool | Purpose |
|------|---------|
| `list_dims` | Top-N values for a dimension with CTR over a time window |
| `query_metric` | Per-minute time series for one dimension value |
| `compare_base` | Current window CTR vs. a 60-min baseline for one value |

---

## Prerequisites

- StarRocks Shared-Data cluster running in namespace `starrocks`  
  (deployed via `../../starrocks-shared-data.yaml`)
- EKS Pod Identity or IRSA wired up for Bedrock access  
  (see **IAM setup** below)
- `kubectl`, `aws` CLI, `docker` available locally
- Claude Sonnet 4.6 model enabled in Amazon Bedrock for your region

---

## IAM setup (one-time)

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
CLUSTER=<your-cluster-name>
OIDC=$(aws eks describe-cluster --name $CLUSTER --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')

# Create IAM role with Bedrock permissions
aws iam create-role \
  --role-name agentic-analytics-agent-role \
  --assume-role-policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Principal\": {\"Federated\": \"arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC}\"},
      \"Action\": \"sts:AssumeRoleWithWebIdentity\",
      \"Condition\": {\"StringEquals\": {
        \"${OIDC}:sub\": \"system:serviceaccount:agentic-analytics:agent-sa\"
      }}
    }]
  }"

aws iam put-role-policy \
  --role-name agentic-analytics-agent-role \
  --policy-name BedrockInvoke \
  --policy-document file://iam-policy.json

# Update serviceaccounts.yaml with the role ARN
sed -i "s/<ACCOUNT_ID>/${ACCOUNT_ID}/g" serviceaccounts.yaml
```

---

## Quick start

```bash
# 1. Set environment variables
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export REGION=us-east-1

# 2. Apply StarRocks schema (run against FE NLB or via kubectl exec)
SR_HOST=$(kubectl get svc starrocks-shared-data-fe-service -n starrocks \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
mysql -h $SR_HOST -P 9030 -u root < starrocks-schema.sql

# 3. Build, push, and deploy everything
./deploy.sh

# 4. Port-forward and test
kubectl port-forward svc/agent 8080:8080 -n agentic-analytics &

curl -s -X POST http://localhost:8080/investigate \
  -H "Content-Type: application/json" \
  -d '{"question":"CTR dropped for advertiser_42 in last 15min — what is the root cause?","advertiser_id":42}' \
  | jq .
```

Expected response (in ~25 s):

```json
{
  "report": "## Root Cause\ncreative_id 8821 for advertiser 42 ...",
  "analysis": "The outlier is creative_id=8821 ...",
  "plan": [...]
}
```

---

## Observability

```bash
# Watch the full investigation trace (plan, tool calls, results, final report)
kubectl logs -f deploy/agent -n agentic-analytics

# Watch MCP server SQL execution
kubectl logs -f deploy/mcp-server -n agentic-analytics
```

---

## What is intentionally not included

| Feature | Reason |
|---------|---------|
| Real-time Kafka ingest | Seed once, query historical — streaming is a v2 concern |
| Agent memory (DynamoDB) | Each investigation is stateless; memory is a v2 feature |
| Langfuse / CloudWatch dashboards | kubectl logs is sufficient for the prototype |
| API Gateway / Ingress | port-forward is fine for demo; add later |
| Slack webhook | Add a 50-line handler when needed for customer demos |

---

## File structure

```
agentic-analytics/
├── README.md
├── deploy.sh               # Build, push, and apply everything
├── iam-policy.json         # Bedrock InvokeModel policy for the agent IAM role
├── namespace.yaml
├── serviceaccounts.yaml    # agent-sa (IRSA) + mcp-sa
├── secret.yaml             # StarRocks credentials
├── starrocks-schema.sql    # ad_events table + 1-min async MV
├── agent/
│   ├── app.py              # LangGraph state machine + FastAPI endpoint
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── deployment.yaml
│   └── service.yaml
├── mcp-server/
│   ├── app.py              # FastAPI + 3 templated SQL tools
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── deployment.yaml
│   └── service.yaml
└── seed-job/
    ├── seed_data.py        # 1M synthetic ad events + injected anomaly
    ├── Dockerfile
    ├── requirements.txt
    └── seed-job.yaml
```
