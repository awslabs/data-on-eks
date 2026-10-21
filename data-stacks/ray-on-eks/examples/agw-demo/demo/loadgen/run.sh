#!/bin/bash
# Run the multi-team load generator as in-cluster Jobs (traffic from inside
# the VPC). One Job per AZ by default so load enters the gateway from 2a/2b/2c.
#   demo/loadgen/run.sh <profile> <duration_s> [zones] [extra loadgen args]
#   demo/loadgen/run.sh mixed 180
#   demo/loadgen/run.sh custom 60 us-west-2a --spec 'team-labs:chat=5'
# Output: kubectl -n agw-demo logs -l app=agw-demo-loadgen --tail=-1
set -euo pipefail
cd "$(dirname "$0")"
export KUBECONFIG="${KUBECONFIG:-$(cd ../../../.. && pwd)/kubeconfig.yaml}"
PROFILE=${1:-mixed}; DURATION=${2:-120}; ZONES=${3:-us-west-2a,us-west-2b,us-west-2c}; shift $(( $# < 3 ? $# : 3 ))
EXTRA="$*"
kubectl -n agw-demo create configmap agw-demo-loadgen --from-file=loadgen.py --from-file=overhead.py \
  --from-file=../../proto/gen/embeddings_pb2.py --from-file=../../proto/gen/embeddings_pb2_grpc.py \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n agw-demo delete job -l app=agw-demo-loadgen --ignore-not-found >/dev/null
RUN=$(date +%H%M%S)
for z in ${ZONES//,/ }; do
  sed -e "s|__ZONE__|$z|g" -e "s|__RUN__|$RUN|g" -e "s|__ZSHORT__|${z##*-}|g" \
      -e "s|__ARGS__|--profile $PROFILE --duration $DURATION $EXTRA|g" job.yaml | kubectl apply -f - >/dev/null
  echo "started loadgen-$RUN-${z##*-} in $z: --profile $PROFILE --duration $DURATION $EXTRA"
done
