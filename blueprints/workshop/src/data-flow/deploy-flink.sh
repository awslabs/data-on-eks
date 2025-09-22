#!/bin/bash

REPO_ROOT=$(git rev-parse --show-toplevel)
PYTHON_FILE="$REPO_ROOT/blueprints/workshop/src/data-flow/raw-ingestion.py"
DEPLOYMENT_FILE="$REPO_ROOT/blueprints/workshop/manifests/flink-deployment.yaml"
OUTPUT_FILE="/tmp/flink-deployment-updated.yaml"

# Use awk to replace the placeholder with file content
awk '
/PYTHON_SCRIPT_CONTENT/ {
    while ((getline line < "'$PYTHON_FILE'") > 0) {
        print "    " line
    }
    close("'$PYTHON_FILE'")
    next
}
{print}
' "$DEPLOYMENT_FILE" > "$OUTPUT_FILE"

# Add restart timestamp
sed -i '' "s/RESTART_TIMESTAMP/$(date +%s)/" "$OUTPUT_FILE"

kubectl apply -f "$OUTPUT_FILE"
echo "Flink deployment updated"
