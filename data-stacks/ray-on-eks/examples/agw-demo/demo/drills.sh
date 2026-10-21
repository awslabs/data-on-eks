#!/bin/bash
# Availability drills. Start background traffic first so errors are visible:
#   ./demo/loadgen/run.sh steady 1200 us-west-2a,us-west-2b,us-west-2c --timeline 5
#   ./demo/drills.sh gateway     # delete one gateway proxy pod
#   ./demo/drills.sh gpu-node    # lose the Gemma GPU node in us-west-2a (spot reclaim / AZ loss)
#   ./demo/drills.sh ray-head    # delete the Gemma Ray head (state recovers from Valkey)
#   ./demo/drills.sh errors 300  # failed requests seen by the load jobs in the last N seconds
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-$(cd "$(dirname "$0")/../../.." && pwd)/kubeconfig.yaml}"
serve_status() {
  local h; h=$(kubectl -n agw-demo get pod -l app=gemma-12b,ray.io/node-type=head -o jsonpath='{.items[?(@.status.containerStatuses[0].ready==true)].metadata.name}')
  [[ -n "$h" ]] && kubectl -n agw-demo exec "$h" -- serve status 2>/dev/null | python3 -c "import sys,yaml; a=yaml.safe_load(sys.stdin)['applications']['llm-app']; print(a['status'], {k.split(':')[0]:v['replica_states'] for k,v in a['deployments'].items()})" 2>/dev/null || echo "head not ready"
}
wait_serving() {
  local t0=$1
  for _ in $(seq 1 60); do
    st=$(serve_status); echo "+$(( $(date +%s)-t0 ))s $st"
    [[ "$st" == RUNNING*"'LLMServer': {'RUNNING': 2}"*"'OpenAiIngress': {'RUNNING': 2}"* ]] && return 0
    sleep 15
  done
}
case "${1:-}" in
  gateway)
    p=$(kubectl -n agentgateway-system get pod -l gateway.networking.k8s.io/gateway-name=agw-demo-gw -o jsonpath='{.items[0].metadata.name}')
    echo "$(date +%T) deleting gateway proxy $p"; kubectl -n agentgateway-system delete pod "$p" --wait=false
    sleep 15; kubectl -n agentgateway-system get pods -l gateway.networking.k8s.io/gateway-name=agw-demo-gw -o wide ;;
  gpu-node)
    n=$(kubectl get nodes -l agw-demo/pool=gpu-gemma,topology.kubernetes.io/zone=us-west-2a -o jsonpath='{.items[0].metadata.name}')
    t0=$(date +%s); echo "$(date +%T) cordon + drain + delete $n (us-west-2a)"
    kubectl cordon "$n"; kubectl drain "$n" --ignore-daemonsets --delete-emptydir-data --timeout=180s >/dev/null
    # Delete the node like a spot reclaim does; Karpenter terminates the instance and launches a replacement.
    kubectl delete node "$n" --wait=false
    wait_serving "$t0"; kubectl get nodes -l agw-demo/pool=gpu-gemma -L topology.kubernetes.io/zone ;;
  ray-head)
    h=$(kubectl -n agw-demo get pod -l app=gemma-12b,ray.io/node-type=head -o jsonpath='{.items[0].metadata.name}')
    t0=$(date +%s); echo "$(date +%T) deleting Ray head $h"; kubectl -n agw-demo delete pod "$h" --wait=false
    sleep 20; wait_serving "$t0"; kubectl -n agw-demo get pods -l app=gemma-12b ;;
  errors)
    kubectl -n agw-demo logs -l app=agw-demo-loadgen --since="${2:-300}s" --prefix | grep ' TL ' | python3 -c "
import sys,re,ast
from collections import defaultdict
ok=defaultdict(int); bad=[]
for l in sys.stdin:
  t=l.split(' TL ')[1].split()[0]
  for k,v in re.findall(r'(\S+/\S+) (\{[^}]*\})', l):
    for c,n in ast.literal_eval(v).items():
      (ok.__setitem__(k, ok[k]+n) if c in ('200','OK') else bad.append((t,k,c,n)))
print('ok:', dict(ok)); print('failed:', len(bad) and sum(b[3] for b in bad)); [print('  ',b) for b in bad]" ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
