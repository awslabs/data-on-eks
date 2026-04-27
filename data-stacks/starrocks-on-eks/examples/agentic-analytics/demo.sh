#!/usr/bin/env bash
# demo.sh — live investigation demo with pre-flight state, real-time progress, and saved report.
#
# What this script does:
#   1. Shows current cluster state (pods, data freshness, anomaly preview)
#   2. Runs the investigation while streaming live agent logs to the terminal
#   3. Renders the full 4-step trace with ANSI colours
#   4. Saves the report to a timestamped file in ./reports/
#
# Usage:
#   CONTEXT=starrocks-on-eks ./demo.sh
#   ./demo.sh "CTR dropped for advertiser_42 in last 15 minutes?"  42

set -euo pipefail

CONTEXT="${CONTEXT:-starrocks-on-eks}"
QUESTION="${1:-CTR dropped for advertiser_42 in last 15 minutes — which creative, placement, device, or country is the root cause?}"
ADVERTISER="${2:-42}"
PORT=8080
NS=agentic-analytics
SR_NS=starrocks
SR_POD=starrocks-shared-data-fe-0
REPORT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/reports"

# ── colours ──────────────────────────────────────────────────────────────────
BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[34m'
RED='\033[31m'; MAGENTA='\033[35m'; WHITE='\033[97m'

SEP="─────────────────────────────────────────────────────────────────"
WIDE="═════════════════════════════════════════════════════════════════"

PF_PID="" LOG_PID=""
cleanup() {
  [[ -n "$PF_PID"  ]] && kill "$PF_PID"  2>/dev/null || true
  [[ -n "$LOG_PID" ]] && kill "$LOG_PID" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$REPORT_DIR"

# ── header ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}${WIDE}${RESET}"
echo -e "${BOLD}${CYAN}  Agentic Analytics — StarRocks + Bedrock + MCP Demo${RESET}"
echo -e "${BOLD}${CYAN}${WIDE}${RESET}"
echo -e "${DIM}  Cluster : ${CONTEXT}${RESET}"
echo -e "${DIM}  Model   : Claude Sonnet 4.6 (Amazon Bedrock via IRSA)${RESET}"
echo -e "${DIM}  MCP     : Official mcp-server-starrocks (Streamable-HTTP)${RESET}"
echo ""

# ── PRE-FLIGHT: cluster state ─────────────────────────────────────────────────
echo -e "${BOLD}${BLUE}❶  PRE-FLIGHT STATE CHECK${RESET}"
echo -e "${DIM}${SEP}${RESET}"

echo -e "\n${BOLD}  Pods (namespace: ${NS})${RESET}"
kubectl --context "$CONTEXT" get pods -n "$NS" \
  --no-headers \
  -o custom-columns='  NAME:.metadata.name,READY:.status.containerStatuses[0].ready,STATUS:.status.phase,AGE:.metadata.creationTimestamp' 2>/dev/null \
  | awk '{printf "  %-45s %-8s %-12s %s\n", $1, $2, $3, $4}' || \
  kubectl --context "$CONTEXT" get pods -n "$NS" 2>/dev/null | sed 's/^/  /'

echo ""
echo -e "${BOLD}  Data freshness (ad_analytics.ad_events)${RESET}"

# Query StarRocks for current state
SR_CMD="kubectl --context $CONTEXT exec -n $SR_NS $SR_POD -- mysql -h 127.0.0.1 -P 9030 -u root"

FRESH=$(${SR_CMD} -e \
  "SELECT COUNT(*) FROM ad_analytics.ad_events WHERE event_ts >= NOW() - INTERVAL 15 MINUTE;" \
  2>/dev/null | tail -1 || echo "0")

TOTAL=$(${SR_CMD} -e \
  "SELECT COUNT(*) FROM ad_analytics.ad_events;" \
  2>/dev/null | tail -1 || echo "0")

MAX_TS=$(${SR_CMD} -e \
  "SELECT MAX(event_ts) FROM ad_analytics.ad_events;" \
  2>/dev/null | tail -1 || echo "unknown")

echo -e "  Total rows   : ${BOLD}${TOTAL}${RESET}"
echo -e "  Latest event : ${BOLD}${MAX_TS}${RESET}"

if [[ "$FRESH" -lt 1000 ]]; then
  echo ""
  echo -e "  ${BOLD}${RED}⚠  WARNING: Only ${FRESH} rows in last 15 min — data may be stale!${RESET}"
  echo -e "  ${DIM}  Re-seed before demoing:${RESET}"
  echo -e "  ${DIM}  kubectl --context $CONTEXT exec -n $SR_NS $SR_POD -- \\${RESET}"
  echo -e "  ${DIM}    mysql -h 127.0.0.1 -P 9030 -u root -e 'TRUNCATE TABLE ad_analytics.ad_events;'${RESET}"
  echo ""
else
  echo -e "  In last 15min: ${BOLD}${GREEN}${FRESH} rows ✓${RESET}"
fi

echo ""
echo -e "${BOLD}  Injected anomaly preview (advertiser_id=${ADVERTISER})${RESET}"
${SR_CMD} -e \
  "SELECT creative_id,
          ROUND(SUM(clicks)/NULLIF(SUM(impressions),0)*100,4) AS ctr_pct,
          SUM(impressions) AS impressions,
          SUM(clicks) AS clicks
   FROM ad_analytics.ad_events
   WHERE advertiser_id=${ADVERTISER} AND event_ts >= NOW() - INTERVAL 15 MINUTE
   GROUP BY creative_id
   ORDER BY ctr_pct ASC
   LIMIT 5;" 2>/dev/null | sed 's/^/  /' || echo "  (unable to query)"

echo ""
echo -e "${DIM}  The agent does NOT know any of this — it will discover it by writing its own SQL queries.${RESET}"
echo ""

# ── port-forward ─────────────────────────────────────────────────────────────
if ! curl -sf http://localhost:${PORT}/health &>/dev/null; then
  echo -e "${DIM}  Starting port-forward → svc/agent:${PORT} ...${RESET}"
  kubectl --context "$CONTEXT" port-forward svc/agent ${PORT}:${PORT} \
    -n "$NS" &>/tmp/pf-demo.log &
  PF_PID=$!
  WAITED=0
  until curl -sf http://localhost:${PORT}/health &>/dev/null; do
    sleep 1; WAITED=$((WAITED+1))
    [[ $WAITED -gt 30 ]] && { echo -e "${RED}Agent not reachable. Check pods.${RESET}"; exit 1; }
  done
  echo -e "${GREEN}  Agent ready.${RESET}\n"
fi

# ── question ─────────────────────────────────────────────────────────────────
echo -e "${BOLD}${WHITE}❷  INVESTIGATION REQUEST${RESET}"
echo -e "${DIM}${SEP}${RESET}"
echo -e "\n  ${BOLD}Question     :${RESET} ${QUESTION}"
echo -e "  ${BOLD}Advertiser ID:${RESET} ${ADVERTISER}"
echo ""

# ── live agent log stream ─────────────────────────────────────────────────────
echo -e "${BOLD}${BLUE}❸  LIVE AGENT PROGRESS${RESET}  ${DIM}(streaming from pod logs)${RESET}"
echo -e "${DIM}${SEP}${RESET}\n"

AGENT_POD=$(kubectl --context "$CONTEXT" get pods -n "$NS" -l app=agent \
  --no-headers -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$AGENT_POD" ]]; then
  # Tail agent logs and highlight key step lines
  kubectl --context "$CONTEXT" logs -f "$AGENT_POD" -n "$NS" -c agent 2>/dev/null \
  | grep --line-buffered -E "=== |Decompose|Execute|Analyze|Report|read_query|Investigation" \
  | while IFS= read -r line; do
      TS=$(date '+%H:%M:%S')
      if echo "$line" | grep -q "DECOMPOSE"; then
        echo -e "  ${BOLD}${BLUE}[${TS}]${RESET} ${CYAN}⬡ STEP 1 · DECOMPOSE${RESET}  Claude is writing SQL queries..."
      elif echo "$line" | grep -q "Decompose"; then
        SECS=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+s' | head -1)
        COUNT=$(echo "$line" | grep -oE '[0-9]+ quer' | grep -oE '[0-9]+')
        echo -e "  ${BOLD}${BLUE}[${TS}]${RESET} ${GREEN}✓ Decompose done${RESET}  ${COUNT:-?} queries planned in ${SECS:-?}"
      elif echo "$line" | grep -q "EXECUTE"; then
        N=$(echo "$line" | grep -oE '[0-9]+' | head -1)
        echo -e "  ${BOLD}${BLUE}[${TS}]${RESET} ${CYAN}⬡ STEP 2 · EXECUTE${RESET}   Running ${N:-?} queries in parallel via MCP server..."
      elif echo "$line" | grep -q "read_query"; then
        DIM=$(echo "$line" | grep -oE '\[.*?\]' | head -1)
        MS=$(echo "$line" | grep -oE '[0-9]+ms' | head -1)
        echo -e "  ${BOLD}${BLUE}[${TS}]${RESET}   ${DIM}↳ query ${DIM}${DIM}${MS}${RESET}"
      elif echo "$line" | grep -q "Execute.*done"; then
        SECS=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+s' | head -1)
        echo -e "  ${BOLD}${BLUE}[${TS}]${RESET} ${GREEN}✓ Execute done${RESET}  All queries complete in ${SECS:-?}"
      elif echo "$line" | grep -q "=== ANALYZE"; then
        echo -e "  ${BOLD}${BLUE}[${TS}]${RESET} ${CYAN}⬡ STEP 3 · ANALYZE${RESET}   Claude is reading results and finding the outlier..."
      elif echo "$line" | grep -q "Analyze"; then
        SECS=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+s' | head -1)
        echo -e "  ${BOLD}${BLUE}[${TS}]${RESET} ${GREEN}✓ Analyze done${RESET}  in ${SECS:-?}"
      elif echo "$line" | grep -q "=== REPORT"; then
        echo -e "  ${BOLD}${BLUE}[${TS}]${RESET} ${CYAN}⬡ STEP 4 · REPORT${RESET}    Claude is writing the incident report..."
      elif echo "$line" | grep -q "Report"; then
        SECS=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+s' | head -1)
        echo -e "  ${BOLD}${BLUE}[${TS}]${RESET} ${GREEN}✓ Report done${RESET}   in ${SECS:-?}"
      elif echo "$line" | grep -q "Investigation"; then
        echo -e "  ${BOLD}${BLUE}[${TS}]${RESET} ${YELLOW}▶ Investigation started${RESET}"
      fi
    done &
  LOG_PID=$!
fi

# ── call the agent ────────────────────────────────────────────────────────────
START_TS=$(date '+%Y-%m-%dT%H:%M:%S')
PAYLOAD=$(printf '{"question":"%s","advertiser_id":%s}' "$QUESTION" "$ADVERTISER")

RESPONSE=$(curl -sf -X POST http://localhost:${PORT}/investigate \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  --max-time 120 2>&1) || {
    [[ -n "$LOG_PID" ]] && kill "$LOG_PID" 2>/dev/null; LOG_PID=""
    echo -e "\n${RED}  Agent call failed.${RESET}"
    echo -e "  ${DIM}Check logs: kubectl --context $CONTEXT logs deploy/agent -n $NS${RESET}"
    exit 1
  }

# Stop log stream
[[ -n "$LOG_PID" ]] && { kill "$LOG_PID" 2>/dev/null; LOG_PID=""; sleep 0.3; }
echo ""

# ── render full trace ─────────────────────────────────────────────────────────
echo -e "\n${BOLD}${BLUE}❹  FULL INVESTIGATION TRACE${RESET}"

python3 - "$RESPONSE" <<'PYEOF'
import json, sys, textwrap, re

raw  = sys.argv[1]
data = json.loads(raw)
trace = data.get("trace", {})
plan  = trace.get("plan", [])
calls = trace.get("tool_calls", [])
timing = trace.get("timing", {})

BOLD  = "\033[1m"; DIM   = "\033[2m"; RESET = "\033[0m"
CYAN  = "\033[36m"; GREEN = "\033[32m"; YELLOW = "\033[33m"
BLUE  = "\033[34m"; RED   = "\033[31m"; WHITE = "\033[97m"
SEP   = "─" * 65
WIDE  = "═" * 65

# ── PLAN ─────────────────────────────────────────────────────────
print(f"\n{BOLD}{BLUE}{WIDE}{RESET}")
print(f"{BOLD}{BLUE}  STEP 1 · DECOMPOSE  "
      f"({len(plan)} drill-downs · {timing.get('decompose_s','?')}s){RESET}")
print(f"{BOLD}{BLUE}{WIDE}{RESET}")
for i, item in enumerate(plan, 1):
    desc = textwrap.shorten(item.get("description", ""), 68)
    print(f"  {i}. {CYAN}[{item.get('dimension','?')}]{RESET}  {desc}")

# ── EXECUTE ───────────────────────────────────────────────────────
print(f"\n{BOLD}{BLUE}{WIDE}{RESET}")
print(f"{BOLD}{BLUE}  STEP 2 · EXECUTE  "
      f"(concurrent · {timing.get('execute_s','?')}s total){RESET}")
print(f"{BOLD}{BLUE}{WIDE}{RESET}")
for c in calls:
    ms = c.get("elapsed_ms", "?")
    dim = c.get("dimension", "?")
    sql_preview = (c.get("sql") or "")[:120]
    preview = (c.get("preview") or "")
    # first 2 data lines from preview
    lines = [l for l in preview.split("\n") if l.strip()][:3]
    print(f"\n  {BOLD}{dim}{RESET}  {DIM}[{ms} ms]{RESET}")
    print(f"  {DIM}SQL: {sql_preview}...{RESET}")
    for l in lines:
        print(f"  {DIM}  {l}{RESET}")

# ── ANALYZE ───────────────────────────────────────────────────────
print(f"\n{BOLD}{YELLOW}{WIDE}{RESET}")
print(f"{BOLD}{YELLOW}  STEP 3 · ANALYZE  ({timing.get('analyze_s','?')}s){RESET}")
print(f"{BOLD}{YELLOW}{WIDE}{RESET}")
analysis = data.get("analysis", "")
# strip markdown bold markers for terminal
clean = re.sub(r'\*\*(.+?)\*\*', lambda m: f"{BOLD}{m.group(1)}{RESET}", analysis)
for line in clean.split("\n"):
    stripped = line.strip()
    if not stripped:
        continue
    if stripped.startswith("##"):
        print(f"\n  {BOLD}{stripped}{RESET}")
    elif stripped.startswith("|"):
        print(f"  {CYAN}{stripped}{RESET}")
    else:
        for wrapped in textwrap.wrap(stripped, 68):
            print(f"  {wrapped}")

# ── REPORT ────────────────────────────────────────────────────────
print(f"\n{BOLD}{GREEN}{WIDE}{RESET}")
print(f"{BOLD}{GREEN}  STEP 4 · REPORT  ({timing.get('report_s','?')}s){RESET}")
print(f"{BOLD}{GREEN}{WIDE}{RESET}")
report = data.get("report", "")
clean_r = re.sub(r'\*\*(.+?)\*\*', lambda m: f"{BOLD}{m.group(1)}{RESET}", report)
for line in clean_r.split("\n"):
    stripped = line.strip()
    if stripped.startswith("##"):
        print(f"\n  {BOLD}{stripped}{RESET}")
    elif stripped.startswith("|"):
        print(f"  {CYAN}{stripped}{RESET}")
    elif stripped.startswith("- ") or stripped.startswith("* "):
        print(f"  {stripped}")
    elif stripped:
        for wrapped in textwrap.wrap(stripped, 68):
            print(f"  {wrapped}")
    else:
        print()

# ── TIMING ────────────────────────────────────────────────────────
print(f"\n{DIM}{SEP}{RESET}")
print(f"{DIM}  ⏱  decompose {timing.get('decompose_s','?')}s"
      f"  │  execute {timing.get('execute_s','?')}s"
      f"  │  analyze {timing.get('analyze_s','?')}s"
      f"  │  report {timing.get('report_s','?')}s"
      f"  │  total {timing.get('total_s','?')}s{RESET}\n")
PYEOF

# ── save report to file ───────────────────────────────────────────────────────
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
REPORT_FILE="${REPORT_DIR}/investigation_${TIMESTAMP}.md"
JSON_FILE="${REPORT_DIR}/investigation_${TIMESTAMP}.json"

# Save raw JSON
echo "$RESPONSE" | python3 -m json.tool > "$JSON_FILE" 2>/dev/null || echo "$RESPONSE" > "$JSON_FILE"

# Save formatted markdown report
python3 - "$RESPONSE" "$START_TS" "$QUESTION" "$ADVERTISER" > "$REPORT_FILE" <<'PYEOF'
import json, sys, textwrap

raw      = sys.argv[1]
ts       = sys.argv[2]
question = sys.argv[3]
adv_id   = sys.argv[4]

data   = json.loads(raw)
trace  = data.get("trace", {})
plan   = trace.get("plan", [])
calls  = trace.get("tool_calls", [])
timing = trace.get("timing", {})

lines = []
lines.append(f"# Agentic Analytics — Investigation Report")
lines.append(f"")
lines.append(f"**Run at:** {ts}  ")
lines.append(f"**Question:** {question}  ")
lines.append(f"**Advertiser ID:** {adv_id}  ")
lines.append(f"**Model:** {trace.get('model','?')}  ")
lines.append(f"**MCP Server:** {trace.get('mcp_server','?')}  ")
lines.append(f"")
lines.append(f"---")
lines.append(f"")

lines.append(f"## Step 1 · Decompose  ({timing.get('decompose_s','?')}s)")
lines.append(f"")
lines.append(f"Claude wrote {len(plan)} targeted SQL queries:")
lines.append(f"")
for i, p in enumerate(plan, 1):
    lines.append(f"{i}. **[{p.get('dimension','?')}]** {p.get('description','')}")
lines.append(f"")

lines.append(f"## Step 2 · Execute  (concurrent · {timing.get('execute_s','?')}s)")
lines.append(f"")
for c in calls:
    lines.append(f"### [{c.get('dimension','?')}]  {c.get('elapsed_ms','?')} ms")
    lines.append(f"")
    lines.append(f"```sql")
    lines.append(c.get('sql','').strip())
    lines.append(f"```")
    lines.append(f"")
    preview = c.get('preview','')
    if preview:
        lines.append(f"**Result preview:**")
        lines.append(f"```")
        lines.append(preview[:800])
        lines.append(f"```")
    lines.append(f"")

lines.append(f"## Step 3 · Analyze  ({timing.get('analyze_s','?')}s)")
lines.append(f"")
lines.append(data.get('analysis',''))
lines.append(f"")

lines.append(f"## Step 4 · Report  ({timing.get('report_s','?')}s)")
lines.append(f"")
lines.append(data.get('report',''))
lines.append(f"")

lines.append(f"---")
lines.append(f"")
lines.append(f"## Timing Summary")
lines.append(f"")
lines.append(f"| Step | Duration |")
lines.append(f"|---|---|")
lines.append(f"| Decompose | {timing.get('decompose_s','?')}s |")
lines.append(f"| Execute (all queries parallel) | {timing.get('execute_s','?')}s |")
lines.append(f"| Analyze | {timing.get('analyze_s','?')}s |")
lines.append(f"| Report | {timing.get('report_s','?')}s |")
lines.append(f"| **Total** | **{timing.get('total_s','?')}s** |")

print('\n'.join(lines))
PYEOF

echo -e "${BOLD}${GREEN}❺  REPORT SAVED${RESET}"
echo -e "${DIM}${SEP}${RESET}"
echo -e ""
echo -e "  ${BOLD}Markdown report :${RESET} ${REPORT_FILE}"
echo -e "  ${BOLD}Raw JSON        :${RESET} ${JSON_FILE}"
echo -e ""
echo -e "  ${DIM}Open the markdown in any viewer, or:${RESET}"
echo -e "  ${DIM}  cat ${REPORT_FILE}${RESET}"
echo -e ""
