#!/usr/bin/env bash
# reseed.sh — truncate ad_events and re-seed 1M fresh rows with anomaly.
# Run this within 15 minutes of your demo so data timestamps are current.
#
# Usage:
#   CONTEXT=starrocks-on-eks ./reseed.sh

CONTEXT="${CONTEXT:-starrocks-on-eks}"
NS=agentic-analytics
SR_NS=starrocks
SR_POD=starrocks-shared-data-fe-0

BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
GREEN='\033[32m'; CYAN='\033[36m'; YELLOW='\033[33m'

echo ""
echo -e "${BOLD}${CYAN}Re-seeding ad_analytics.ad_events ...${RESET}"
echo ""

echo -e "${DIM}  Truncating existing data ...${RESET}"
kubectl --context "$CONTEXT" exec -n "$SR_NS" "$SR_POD" -- \
  mysql -h 127.0.0.1 -P 9030 -u root \
  -e "TRUNCATE TABLE ad_analytics.ad_events;" 2>/dev/null && \
  echo -e "${GREEN}  ✓ Table truncated${RESET}" || \
  echo -e "  (truncate skipped — table may already be empty)"

echo -e "${DIM}  Deleting old seed job ...${RESET}"
kubectl --context "$CONTEXT" delete job seed-data -n "$NS" --ignore-not-found 2>/dev/null

echo -e "${DIM}  Submitting seed job (inserts 1M rows, ~3 min) ...${RESET}"
kubectl --context "$CONTEXT" apply -f - <<'EOF'
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
            - {name: STARROCKS_USER, value: root}
            - {name: STARROCKS_PASSWORD, value: ""}
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

echo -e "${DIM}  Waiting for seed job to complete ...${RESET}"
kubectl --context "$CONTEXT" wait --for=condition=complete job/seed-data \
  -n "$NS" --timeout=600s

echo ""
echo -e "${BOLD}${GREEN}✓ Done.${RESET} 1M rows loaded with anomaly (creative_id=8821, CTR=0%)."
echo -e "${DIM}  Run the demo within the next 15 minutes:${RESET}"
echo -e "  CONTEXT=${CONTEXT} ./demo.sh"
echo ""
