#!/usr/bin/env bash
# demo.sh — run an investigation and render the full trace in the terminal.
#
# Usage:
#   ./demo.sh
#   ./demo.sh "CTR dropped for advertiser_42 in last 15 minutes?"  42
#
# Prerequisites: kubectl context "starrocks-on-eks" configured, python3 in PATH.

set -euo pipefail

CONTEXT="${CONTEXT:-starrocks-on-eks}"
QUESTION="${1:-CTR dropped for advertiser_42 in last 15 minutes — which creative, placement, device, or country is the root cause?}"
ADVERTISER="${2:-42}"
PORT=8080

# ── colours ──────────────────────────────────────────────────────────────────
BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[34m'; RED='\033[31m'

PF_PID=""
cleanup() { [[ -n "$PF_PID" ]] && kill "$PF_PID" 2>/dev/null || true; }
trap cleanup EXIT

# ── port-forward ─────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${CYAN}Agentic Analytics — StarRocks Investigation Demo${RESET}"
echo -e "${DIM}Cluster: ${CONTEXT}  │  Model: Claude Sonnet 4.6 (Bedrock)${RESET}\n"

if ! curl -sf http://localhost:${PORT}/health &>/dev/null; then
  echo -e "${DIM}Starting port-forward to svc/agent ...${RESET}"
  kubectl --context "$CONTEXT" port-forward svc/agent ${PORT}:${PORT} \
    -n agentic-analytics &>/tmp/pf-demo.log &
  PF_PID=$!
  until curl -sf http://localhost:${PORT}/health &>/dev/null; do sleep 1; done
fi

echo -e "${BOLD}▶  Question:${RESET} ${QUESTION}"
echo -e "${DIM}   advertiser_id=${ADVERTISER}${RESET}\n"
echo -e "${YELLOW}⏳  Running investigation ...${RESET}\n"

# ── call the agent ────────────────────────────────────────────────────────────
PAYLOAD=$(printf '{"question":"%s","advertiser_id":%s}' "$QUESTION" "$ADVERTISER")
RESPONSE=$(curl -sf -X POST http://localhost:${PORT}/investigate \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" 2>&1) || {
    echo -e "${RED}Agent call failed. Check: kubectl logs deploy/agent -n agentic-analytics${RESET}"
    exit 1
  }

# ── render ────────────────────────────────────────────────────────────────────
python3 - "$RESPONSE" <<'PYEOF'
import json, sys, textwrap

raw  = sys.argv[1]
data = json.loads(raw)
trace = data.get("trace", {})
plan  = trace.get("plan", [])
calls = trace.get("tool_calls", [])
timing = trace.get("timing", {})

SEP  = "─" * 62
WIDE = "═" * 62

# ── PLAN ─────────────────────────────────────────────────────────────────────
print(f"\n\033[1m\033[34m{WIDE}\033[0m")
print(f"\033[1m\033[34m  STEP 1 · DECOMPOSE  ({len(plan)} drill-downs, {timing.get('decompose_s','?')}s)\033[0m")
print(f"\033[1m\033[34m{WIDE}\033[0m")
for i, item in enumerate(plan, 1):
    desc = textwrap.shorten(item.get("description",""), 70)
    print(f"  {i}. \033[36m[{item['dimension']}]\033[0m  {desc}")

# ── TOOL CALLS ────────────────────────────────────────────────────────────────
print(f"\n\033[1m\033[34m{WIDE}\033[0m")
print(f"\033[1m\033[34m  STEP 2 · EXECUTE  (concurrent — {timing.get('execute_s','?')}s total)\033[0m")
print(f"\033[1m\033[34m{WIDE}\033[0m")
for c in calls:
    print(f"\n  \033[1m{c['dimension']}\033[0m  [{c.get('elapsed_ms','?')} ms]")
    print(f"  \033[2mSQL: {c.get('sql','')[:100]}...\033[0m")

    rows = c.get("top_3_rows", [])
    if rows:
        cols = list(rows[0].keys())
        hdr  = "  │  ".join(f"{col:<14}" for col in cols)
        print(f"  {hdr}")
        print(f"  {SEP}")
        for row in rows:
            line = "  │  ".join(str(row.get(col,""))[:14].ljust(14) for col in cols)
            print(f"  {line}")

    compare = c.get("compare_vs_baseline", [])
    if compare:
        print(f"  \033[33mBaseline comparison:\033[0m")
        for r in compare:
            period = r.get("period","")
            ctr    = r.get("ctr_pct","?")
            impr   = r.get("impressions","?")
            print(f"    {period:<10} ctr={ctr}%  impressions={impr}")

# ── ANALYZE ───────────────────────────────────────────────────────────────────
print(f"\n\033[1m\033[34m{WIDE}\033[0m")
print(f"\033[1m\033[34m  STEP 3 · ANALYZE  ({timing.get('analyze_s','?')}s)\033[0m")
print(f"\033[1m\033[34m{WIDE}\033[0m")
analysis = data.get("analysis","")
for line in textwrap.wrap(analysis, 70):
    print(f"  {line}")

# ── REPORT ────────────────────────────────────────────────────────────────────
print(f"\n\033[1m\033[32m{WIDE}\033[0m")
print(f"\033[1m\033[32m  STEP 4 · REPORT  ({timing.get('report_s','?')}s)\033[0m")
print(f"\033[1m\033[32m{WIDE}\033[0m")
for line in data.get("report","").split("\n"):
    if line.startswith("##"):
        print(f"\n\033[1m{line}\033[0m")
    elif line.startswith("|"):
        print(f"  \033[36m{line}\033[0m")
    else:
        print(f"  {line}")

# ── TIMING ────────────────────────────────────────────────────────────────────
print(f"\n\033[2m{SEP}\033[0m")
print(f"\033[2m  ⏱  decompose {timing.get('decompose_s','?')}s"
      f"  │  execute {timing.get('execute_s','?')}s"
      f"  │  analyze {timing.get('analyze_s','?')}s"
      f"  │  report {timing.get('report_s','?')}s"
      f"  │  total {timing.get('total_s','?')}s\033[0m\n")
PYEOF
