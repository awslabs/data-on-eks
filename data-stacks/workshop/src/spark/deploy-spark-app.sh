#!/bin/bash
set -euo pipefail

# This script deploys the SparkApplication custom resource.
# It dynamically injects the python script into the ConfigMap,
# substitutes environment variables, and applies the manifest.

# Ensure the script is run from the same directory as the other files.
cd "$(dirname "$0")"

# Provide a default for S3_WAREHOUSE_PATH if not set, to avoid issues with envsubst.
export S3_WAREHOUSE_PATH="s3a://${S3_BUCKET}/iceberg-warehouse/"

# --- Fix for indentation ---
# Create a temporary file to hold the indented version of the python script.
# The script content must be indented by 4 spaces to be valid YAML under the ConfigMap data key.
INDENTED_SCRIPT_TMP=$(mktemp)

# Use a trap to ensure the temp file is always cleaned up, even if the script fails.
trap 'rm -f "$INDENTED_SCRIPT_TMP"' EXIT

# Use sed to add 4 spaces to the beginning of each line.
sed 's/^/    /' cat-summary.py > "$INDENTED_SCRIPT_TMP"
# ---

echo "Deploying Spark Application: cat-summary"
echo "Using S3 Warehouse Path: $S3_WAREHOUSE_PATH"

# 1. Use sed to replace the placeholder with the content of the (now indented) python script.
# 2. Pipe to envsubst to replace ${S3_WAREHOUSE_PATH}.
# 3. Pipe to kubectl to apply the resulting manifest.
sed -e "/^    # PYTHON_SCRIPT_GOES_HERE/r $INDENTED_SCRIPT_TMP" -e '/^    # PYTHON_SCRIPT_GOES_HERE/d' spark-app.yaml | \
envsubst | \
kubectl apply -f -

echo "SparkApplication 'cat-summary' deployed successfully."