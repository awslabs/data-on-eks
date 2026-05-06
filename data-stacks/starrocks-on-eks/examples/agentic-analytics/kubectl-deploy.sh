#!/usr/bin/env bash
# kubectl-deploy.sh — deploy the agentic-analytics stack without building Docker images.
#
# Strategy:
#   - Official StarRocks MCP server: installed via uv (mcp-server-starrocks==0.3.0)
#   - Agent: Python source stored in a ConfigMap, run from python:3.12-slim
#   - Both use uv init containers; no ECR or Docker builds required.
#
# Prerequisites:
#   - kubectl configured for the target cluster (starrocks-on-eks)
#   - aws CLI authenticated (needed for IRSA role creation)
#   - StarRocks Shared-Data cluster running in namespace "starrocks"
#   - Bedrock model enabled: us.anthropic.claude-sonnet-4-6
#
# Usage:
#   export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
#   export CLUSTER=starrocks-on-eks
#   export REGION=us-east-1
#   ./kubectl-deploy.sh

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# Prompt for required environment variables if not set
# ──────────────────────────────────────────────────────────────────────────────
if [[ -z "${ACCOUNT_ID:-}" ]]; then
  echo "ACCOUNT_ID is not set."
  echo ""
  echo "  Please export the following before running this script:"
  echo ""
  echo "    export ACCOUNT_ID=\$(aws sts get-caller-identity --query Account --output text)"
  echo "    export CLUSTER=starrocks-on-eks    # optional, defaults to starrocks-on-eks"
  echo "    export REGION=us-east-1            # optional, defaults to us-east-1"
  echo "    ./kubectl-deploy.sh"
  echo ""
  exit 1
fi

ACCOUNT_ID="${ACCOUNT_ID}"
CLUSTER="${CLUSTER:-starrocks-on-eks}"
REGION="${REGION:-us-east-1}"
CONTEXT="${CONTEXT:-$CLUSTER}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KC="kubectl --context $CONTEXT"

# ──────────────────────────────────────────────────────────────────────────────
# 1. IAM IRSA role
# ──────────────────────────────────────────────────────────────────────────────
echo "==> Setting up IRSA role ..."
OIDC_HOST=$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')

ROLE_NAME="agentic-analytics-agent-role"
aws iam get-role --role-name "$ROLE_NAME" > /dev/null 2>&1 || \
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "{
      \"Version\": \"2012-10-17\",
      \"Statement\": [{
        \"Effect\": \"Allow\",
        \"Principal\": {\"Federated\": \"arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_HOST}\"},
        \"Action\": \"sts:AssumeRoleWithWebIdentity\",
        \"Condition\": {\"StringEquals\": {
          \"${OIDC_HOST}:sub\": \"system:serviceaccount:agentic-analytics:agent-sa\",
          \"${OIDC_HOST}:aud\": \"sts.amazonaws.com\"
        }}
      }]
    }" > /dev/null

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "BedrockInvoke" \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Sid\": \"BedrockFoundationModels\",
        \"Effect\": \"Allow\",
        \"Action\": \"bedrock:InvokeModel\",
        \"Resource\": \"arn:aws:bedrock:*::foundation-model/anthropic.claude-*\"
      },
      {
        \"Sid\": \"BedrockInferenceProfiles\",
        \"Effect\": \"Allow\",
        \"Action\": \"bedrock:InvokeModel\",
        \"Resource\": \"arn:aws:bedrock:*:${ACCOUNT_ID}:inference-profile/*\"
      }
    ]
  }"

echo "    IAM role arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME} ready."

# ──────────────────────────────────────────────────────────────────────────────
# 2. Namespace + RBAC
# ──────────────────────────────────────────────────────────────────────────────
echo "==> Applying namespace, service accounts, and secret ..."
sed "s/<ACCOUNT_ID>/${ACCOUNT_ID}/g" "$SCRIPT_DIR/base.yaml" | $KC apply -f -

# ──────────────────────────────────────────────────────────────────────────────
# 3. StarRocks schema
# ──────────────────────────────────────────────────────────────────────────────
echo "==> Applying StarRocks schema ..."
$KC exec -i -n starrocks starrocks-shared-data-fe-0 -- \
  mysql -h 127.0.0.1 -P 9030 -u root < "$SCRIPT_DIR/starrocks-schema.sql"

# ──────────────────────────────────────────────────────────────────────────────
# 4. ConfigMaps (agent source + seed job)
# ──────────────────────────────────────────────────────────────────────────────
echo "==> Creating code ConfigMaps ..."
$KC create configmap agent-code \
  --from-file=app.py="$SCRIPT_DIR/agent/app.py" \
  --from-file=pyproject.toml="$SCRIPT_DIR/agent/pyproject.toml" \
  -n agentic-analytics --dry-run=client -o yaml | $KC apply -f -

$KC create configmap seed-job-code \
  --from-file=seed_data.py="$SCRIPT_DIR/seed-job/seed_data.py" \
  --from-file=pyproject.toml="$SCRIPT_DIR/seed-job/pyproject.toml" \
  -n agentic-analytics --dry-run=client -o yaml | $KC apply -f -

# ──────────────────────────────────────────────────────────────────────────────
# 5. Deployments + services
#    mcp-server: official mcp-server-starrocks==0.3.0 (no custom app.py needed)
#    agent:      custom LangGraph app stored in ConfigMap
# ──────────────────────────────────────────────────────────────────────────────
echo "==> Deploying mcp-server (official mcp-server-starrocks==0.3.0) ..."
$KC apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcp-server
  namespace: agentic-analytics
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mcp-server
  template:
    metadata:
      labels:
        app: mcp-server
    spec:
      serviceAccountName: mcp-sa
      initContainers:
        - name: uv-install
          image: ghcr.io/astral-sh/uv:python3.12-trixie-slim
          command: ["uv", "pip", "install", "--no-cache",
                    "--target", "/deps",
                    "mcp-server-starrocks==0.3.0"]
          volumeMounts:
            - {name: deps, mountPath: /deps}
      containers:
        - name: mcp-server
          image: python:3.12-slim
          command:
            - python
            - -c
            - |
              import sys
              sys.path.insert(0, '/deps')
              from mcp_server_starrocks import main
              import asyncio
              sys.argv = ['mcp-server-starrocks', '--mode', 'streamable-http',
                          '--host', '0.0.0.0', '--port', '8000']
              asyncio.run(main())
          env:
            - {name: PYTHONPATH, value: /deps}
            - {name: STARROCKS_HOST, value: starrocks-shared-data-fe-service.starrocks.svc.cluster.local}
            - {name: STARROCKS_PORT, value: "9030"}
            - name: STARROCKS_USER
              valueFrom: {secretKeyRef: {name: starrocks-creds, key: user}}
            - name: STARROCKS_PASSWORD
              valueFrom: {secretKeyRef: {name: starrocks-creds, key: password}}
            - {name: STARROCKS_DB, value: ad_analytics}
            - {name: MCP_TRANSPORT_MODE, value: streamable-http}
            - {name: LOG_LEVEL, value: INFO}
          ports: [{containerPort: 8000}]
          resources:
            requests: {cpu: 500m, memory: 1Gi}
            limits: {cpu: "1", memory: 2Gi}
          readinessProbe:
            tcpSocket: {port: 8000}
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 6
          volumeMounts:
            - {name: deps, mountPath: /deps}
      volumes:
        - {name: deps, emptyDir: {}}
---
apiVersion: v1
kind: Service
metadata:
  name: mcp-server
  namespace: agentic-analytics
spec:
  selector: {app: mcp-server}
  ports: [{name: http, port: 8000, targetPort: 8000}]
  type: ClusterIP
EOF

echo "==> Deploying agent ..."
$KC apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: agent
  namespace: agentic-analytics
spec:
  replicas: 1
  selector:
    matchLabels:
      app: agent
  template:
    metadata:
      labels:
        app: agent
    spec:
      serviceAccountName: agent-sa
      initContainers:
        - name: uv-install
          image: ghcr.io/astral-sh/uv:python3.12-trixie-slim
          command: ["uv", "pip", "install", "--no-cache", "--target", "/deps", "-r", "/code/pyproject.toml"]
          volumeMounts:
            - {name: code, mountPath: /code}
            - {name: deps, mountPath: /deps}
      containers:
        - name: agent
          image: python:3.12-slim
          command: ["python", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
          workingDir: /code
          env:
            - {name: PYTHONPATH, value: /deps}
            - {name: AWS_REGION, value: ${REGION}}
            - {name: BEDROCK_MODEL_ID, value: us.anthropic.claude-sonnet-4-6}
            - {name: MCP_SERVER_URL, value: "http://mcp-server.agentic-analytics.svc.cluster.local:8000/mcp"}
          ports: [{containerPort: 8080}]
          resources:
            requests: {cpu: 500m, memory: 512Mi}
            limits: {cpu: "1", memory: 1Gi}
          readinessProbe:
            httpGet: {path: /health, port: 8080}
            initialDelaySeconds: 15
            periodSeconds: 5
          volumeMounts:
            - {name: code, mountPath: /code}
            - {name: deps, mountPath: /deps}
      volumes:
        - {name: code, configMap: {name: agent-code}}
        - {name: deps, emptyDir: {}}
---
apiVersion: v1
kind: Service
metadata:
  name: agent
  namespace: agentic-analytics
spec:
  selector: {app: agent}
  ports: [{name: http, port: 8080, targetPort: 8080}]
  type: ClusterIP
EOF

# ──────────────────────────────────────────────────────────────────────────────
# 6. Wait for both deployments, then run seed job
# ──────────────────────────────────────────────────────────────────────────────
echo "==> Waiting for deployments (uv install takes ~60s on first run) ..."
$KC rollout status deployment/mcp-server -n agentic-analytics
$KC rollout status deployment/agent      -n agentic-analytics

echo "==> Running seed job (inserts 1M rows with anomaly, ~3 min) ..."
$KC apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: seed-data
  namespace: agentic-analytics
spec:
  ttlSecondsAfterFinished: 600
  template:
    spec:
      serviceAccountName: mcp-sa
      restartPolicy: Never
      initContainers:
        - name: uv-install
          image: ghcr.io/astral-sh/uv:python3.12-trixie-slim
          command: ["uv", "pip", "install", "--no-cache", "--target", "/deps", "-r", "/code/pyproject.toml"]
          volumeMounts:
            - {name: code, mountPath: /code}
            - {name: deps, mountPath: /deps}
      containers:
        - name: seed
          image: python:3.12-slim
          command: ["python", "/code/seed_data.py"]
          env:
            - {name: PYTHONPATH, value: /deps}
            - {name: STARROCKS_HOST, value: starrocks-shared-data-fe-service.starrocks.svc.cluster.local}
            - {name: STARROCKS_PORT, value: "9030"}
            - {name: STARROCKS_DATABASE, value: ad_analytics}
            - name: STARROCKS_USER
              valueFrom: {secretKeyRef: {name: starrocks-creds, key: user}}
            - name: STARROCKS_PASSWORD
              valueFrom: {secretKeyRef: {name: starrocks-creds, key: password}}
          resources:
            requests: {cpu: 500m, memory: 2Gi}
            limits: {cpu: "1", memory: 3Gi}
          volumeMounts:
            - {name: code, mountPath: /code}
            - {name: deps, mountPath: /deps}
      volumes:
        - {name: code, configMap: {name: seed-job-code}}
        - {name: deps, emptyDir: {}}
EOF

$KC wait --for=condition=complete job/seed-data -n agentic-analytics --timeout=600s
echo ""
echo "==> Stack is ready.  Run the demo:"
echo ""
echo "  CONTEXT=${CONTEXT} ./demo.sh"
echo ""
echo "  Or manually:"
echo "  kubectl --context ${CONTEXT} port-forward svc/agent 8080:8080 -n agentic-analytics &"
echo '  curl -s -X POST http://localhost:8080/investigate \'
echo '    -H "Content-Type: application/json" \'
echo '    -d '"'"'{"question":"CTR dropped for advertiser_42 in last 15min?","advertiser_id":42}'"'"' | jq .'
echo ""
echo "  NOTE: Seed data is timestamp-relative. Re-seed within 15 min of demo:"
echo "  CONTEXT=${CONTEXT} ./reseed.sh"
echo ""
echo "  To tear down all resources:"
echo "  ACCOUNT_ID=${ACCOUNT_ID} CLUSTER=${CLUSTER} REGION=${REGION} ./cleanup.sh"
