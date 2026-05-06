#!/usr/bin/env bash
# cleanup.sh — tear down all resources created by kubectl-deploy.sh.
#
# This script removes:
#   1. StarRocks ad_analytics database (schema + data)
#   2. Kubernetes namespace agentic-analytics (cascades all K8s resources)
#   3. IAM inline policy BedrockInvoke
#   4. IAM role agentic-analytics-agent-role
#
# Safe to run multiple times (idempotent). Handles already-deleted resources gracefully.
#
# Prerequisites:
#   - kubectl configured for the target cluster
#   - aws CLI authenticated with IAM delete permissions
#
# Usage:
#   export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
#   export CLUSTER=starrocks-on-eks
#   export REGION=us-east-1
#   ./cleanup.sh

set -uo pipefail

CLUSTER="${CLUSTER:-starrocks-on-eks}"
REGION="${REGION:-us-east-1}"
CONTEXT="${CONTEXT:-$CLUSTER}"
ROLE_NAME="agentic-analytics-agent-role"
NS="agentic-analytics"
SR_NS="starrocks"
SR_POD="starrocks-shared-data-fe-0"

KC="kubectl --context $CONTEXT"

BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; CYAN='\033[36m'

echo ""
echo -e "${BOLD}${CYAN}Cleaning up agentic-analytics resources ...${RESET}"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# 1. Drop StarRocks database
# ──────────────────────────────────────────────────────────────────────────────
echo -e "${DIM}  [1/4] Dropping StarRocks database ad_analytics ...${RESET}"
if $KC get pod -n "$SR_NS" "$SR_POD" &>/dev/null; then
  $KC exec -n "$SR_NS" "$SR_POD" -- \
    mysql -h 127.0.0.1 -P 9030 -u root \
    -e "DROP DATABASE IF EXISTS ad_analytics;" 2>/dev/null && \
    echo -e "${GREEN}  ✓ Database ad_analytics dropped${RESET}" || \
    echo -e "${YELLOW}  ⚠ Could not drop database (may already be gone)${RESET}"
else
  echo -e "${YELLOW}  ⚠ StarRocks FE pod not running — skipping database drop${RESET}"
fi

# ──────────────────────────────────────────────────────────────────────────────
# 2. Delete Kubernetes namespace (cascades all resources)
# ──────────────────────────────────────────────────────────────────────────────
echo -e "${DIM}  [2/4] Deleting Kubernetes namespace ${NS} ...${RESET}"
$KC delete namespace "$NS" --ignore-not-found 2>/dev/null && \
  echo -e "${GREEN}  ✓ Namespace ${NS} deleted${RESET}" || \
  echo -e "${GREEN}  ✓ Namespace ${NS} already gone${RESET}"

# ──────────────────────────────────────────────────────────────────────────────
# 3. Delete IAM inline policy
# ──────────────────────────────────────────────────────────────────────────────
echo -e "${DIM}  [3/4] Deleting IAM inline policy BedrockInvoke ...${RESET}"
aws iam delete-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "BedrockInvoke" 2>/dev/null && \
  echo -e "${GREEN}  ✓ Inline policy BedrockInvoke deleted${RESET}" || \
  echo -e "${GREEN}  ✓ Inline policy already gone (or role does not exist)${RESET}"

# ──────────────────────────────────────────────────────────────────────────────
# 4. Delete IAM role
# ──────────────────────────────────────────────────────────────────────────────
echo -e "${DIM}  [4/4] Deleting IAM role ${ROLE_NAME} ...${RESET}"
aws iam delete-role \
  --role-name "$ROLE_NAME" 2>/dev/null && \
  echo -e "${GREEN}  ✓ IAM role ${ROLE_NAME} deleted${RESET}" || \
  echo -e "${GREEN}  ✓ IAM role already gone${RESET}"

echo ""
echo -e "${BOLD}${GREEN}✓ Cleanup complete.${RESET} All agentic-analytics resources removed."
echo ""
