#!/bin/bash
set -euo pipefail

NS=clickhouse-tests
TOTAL_SHARDS=3
CH_PW=$(kubectl get secret -n "$NS" clickhouse-password -o jsonpath='{.data.password}' | base64 -d)
FILE=hits.parquet

declare -A PIDS
for SHARD in 0 1 2; do
  POD="tests-clickhouse-${SHARD}-0-0"
  echo "[$(date +%T)] Loading shard $SHARD via $POD..."
  (
    clickhouse local --query "
      SELECT * FROM file('${FILE}', 'Parquet')
      WHERE cityHash64(UserID) % ${TOTAL_SHARDS} = ${SHARD}
      FORMAT Parquet
      SETTINGS input_format_parquet_use_native_reader_v3 = 0
    " \
    | kubectl exec -i -n "$NS" "$POD" -- \
        clickhouse-client --password "$CH_PW" \
          --input_format_parquet_use_native_reader_v3=0 \
          --max_insert_block_size=1048576 \
          --query "INSERT INTO demo.hits_local FORMAT Parquet"
  ) &
  PIDS[$SHARD]=$!
done

FAIL=0
for SHARD in "${!PIDS[@]}"; do
  if ! wait "${PIDS[$SHARD]}"; then
    echo "[$(date +%T)] shard $SHARD FAILED"
    FAIL=1
  else
    echo "[$(date +%T)] shard $SHARD ok"
  fi
done
exit $FAIL
