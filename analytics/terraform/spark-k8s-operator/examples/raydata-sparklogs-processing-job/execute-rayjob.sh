#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# CONFIGURATION SECTION - UPDATE THESE VALUES
# =============================================================================

# These should match your parent Terraform module configuration
NAMESPACE="raydata"
AWS_REGION="us-west-2" # UPDATE: Match your AWS region

# Iceberg Configuration
ICEBERG_CATALOG_TYPE="glue"
ICEBERG_DATABASE="raydata_spark_logs"
ICEBERG_TABLE="spark_logs"

# S3 Configuration (should match Terraform module)
S3_BUCKET="spark-operator-doeks-spark-logs-20250728032843914000000001"  # Replace with your actual S3 bucket name. DON'T USE FIND and REPLACE!
S3_PREFIX="spark-operator-doeks/spark-application-logs/spark-team-a"

# Ray Configuration (can override Terraform defaults)
BATCH_SIZE="10000"
MIN_WORKERS="2"
MAX_WORKERS="10"
INITIAL_WORKERS="2"

# =============================================================================
# END CONFIGURATION SECTION
# =============================================================================


print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}


print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}


print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}


print_header() {
    echo -e "${BLUE}==== $1 ====${NC}"
}


# Function to validate prerequisites
validate_prerequisites() {
    print_header "Validating Prerequisites"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        exit 1
    fi

    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    # Check if namespace exists (created by Terraform module)
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        print_error "Namespace '$NAMESPACE' not found!"
        print_error "Please deploy Terraform infrastructure first:"
        print_error "  terraform apply  # From your parent EKS project"
        print_error "Expected module: raydata_pipeline"
        exit 1
    fi

    # Check if service account exists (created by Terraform module)
    if ! kubectl get serviceaccount raydata -n "$NAMESPACE" &> /dev/null; then
        print_error "Service account 'raydata' not found in namespace '$NAMESPACE'!"
        print_error "Please deploy Terraform infrastructure first."
        print_error "Check that the raydata_pipeline module is properly configured."
        exit 1
    fi

    print_status "✅ Prerequisites validated"
    print_status "✅ Terraform module infrastructure detected"
    print_status "✅ Ray service account found"
}


# Function to validate configuration
validate_config() {
    print_header "Validating Configuration"

    local errors=0

    if [[ -z "$S3_BUCKET" || "$S3_BUCKET" == "<ENTER_S3_BUCKET>" ]]; then
        print_error "S3_BUCKET needs to be updated"
        print_error "Please replace <ENTER_S3_BUCKET> with your actual S3 bucket name"
        errors=$((errors + 1))
    fi

    if [[ "$S3_PREFIX" == *"<ENTER_CLUSTER_NAME>"* ]]; then
        print_error "S3_PREFIX contains placeholder <ENTER_CLUSTER_NAME>"
        print_error "Please replace <ENTER_CLUSTER_NAME> with your actual cluster name"
        errors=$((errors + 1))
    fi

    if [[ $errors -gt 0 ]]; then
        print_error "Please update the configuration section in this script"
        exit 1
    fi

    print_status "✅ Configuration validation passed"
    print_status "✅ Iceberg will use AWS Glue catalog and S3 storage"
}


# Function to update YAML files with variables
update_yaml_files() {
    print_header "Updating YAML Files with Configuration"

    # Check if files exist
    for file in configmap.yaml rayjob.yaml; do
        if [[ ! -f "$file" ]]; then
            print_error "Required file $file not found!"
            exit 1
        fi
    done

    # Calculate Iceberg warehouse path
    ICEBERG_WAREHOUSE="s3://$S3_BUCKET/iceberg-warehouse"

    print_status "Iceberg warehouse path: $ICEBERG_WAREHOUSE"

    # Create temporary files with variable substitution
    for file in configmap.yaml rayjob.yaml; do
        cp "$file" "${file}.tmp"

        # Replace variables used in the YAML files
        sed -i.bak \
            -e "s|\$NAMESPACE|$NAMESPACE|g" \
            -e "s|\$S3_BUCKET|$S3_BUCKET|g" \
            -e "s|\$S3_PREFIX|$S3_PREFIX|g" \
            -e "s|\$ICEBERG_CATALOG_TYPE|$ICEBERG_CATALOG_TYPE|g" \
            -e "s|\$ICEBERG_DATABASE|$ICEBERG_DATABASE|g" \
            -e "s|\$ICEBERG_TABLE|$ICEBERG_TABLE|g" \
            -e "s|\$ICEBERG_WAREHOUSE|$ICEBERG_WAREHOUSE|g" \
            -e "s|\$BATCH_SIZE|$BATCH_SIZE|g" \
            -e "s|\$MIN_WORKERS|$MIN_WORKERS|g" \
            -e "s|\$MAX_WORKERS|$MAX_WORKERS|g" \
            -e "s|\$INITIAL_WORKERS|$INITIAL_WORKERS|g" \
            "${file}.tmp"

        print_status "✅ Updated $file"
    done
}


# Function to deploy Ray job components
deploy_components() {
    print_header "Deploying Ray Job Components"

    print_status "1. Deploying ConfigMap..."
    kubectl apply -f configmap.yaml.tmp

    # Wait a moment for ConfigMap to be ready
    sleep 2

    print_status "2. Deploying RayJob..."
    kubectl apply -f rayjob.yaml.tmp

    print_status "✅ Ray job components deployed successfully"
}


# Function to check status
check_status() {
    print_header "Checking Deployment Status"

    print_status "Ray Job Status:"
    kubectl get rayjob -n "$NAMESPACE" || print_warning "No RayJobs found yet"

    echo ""
    print_status "Pod Status:"
    kubectl get pods -n "$NAMESPACE" -l app=spark-log-processor-job || print_warning "No pods found yet"

    echo ""
    print_status "Services:"
    kubectl get svc -n "$NAMESPACE" || print_warning "No services found yet"
}

# Function to show logs
show_logs() {
    print_header "Ray Job Logs"

    # First, try to find the actual Ray job pod (the one that runs your processing code)
    local job_pod=$(kubectl get pods -n "$NAMESPACE" -l job-name=spark-log-processing-job -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -n "$job_pod" ]]; then
        print_status "Showing logs from Ray job pod: $job_pod"
        kubectl logs "$job_pod" -n "$NAMESPACE" --tail=100 -f
        return
    fi

    # Fallback: Look for pods with spark-log-processing pattern
    local processing_pod=$(kubectl get pods -n "$NAMESPACE" --no-headers | grep -E "spark-log-processing-job-[a-z0-9]+" | head -1 | awk '{print $1}')

    if [[ -n "$processing_pod" ]]; then
        print_status "Showing logs from processing pod: $processing_pod"
        kubectl logs "$processing_pod" -n "$NAMESPACE" --tail=100 -f
        return
    fi

    # Another fallback: Look for any pod containing "spark-log"
    local spark_pod=$(kubectl get pods -n "$NAMESPACE" -o name | grep -i spark-log | head -1 | cut -d'/' -f2)

    if [[ -n "$spark_pod" ]]; then
        print_status "Showing logs from spark log pod: $spark_pod"
        kubectl logs "$spark_pod" -n "$NAMESPACE" --tail=100 -f
        return
    fi

    # Last resort: Show head pod logs
    local head_pod=$(kubectl get pods -n "$NAMESPACE" -l component=ray-head -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -n "$head_pod" ]]; then
        print_status "Showing logs from head pod: $head_pod"
        kubectl logs "$head_pod" -n "$NAMESPACE" --tail=50 -f
    else
        print_warning "No Ray job pods found yet. Checking all pods..."
        echo ""
        print_status "Available pods:"
        kubectl get pods -n "$NAMESPACE"
        echo ""
        print_status "To manually check logs from a specific pod, run:"
        echo "kubectl logs <pod-name> -n $NAMESPACE -f"
    fi
}

# Function to monitor job
monitor_job() {
    print_header "Monitoring Ray Job Progress"

    local job_name="spark-log-processing-job"

    print_status "Monitoring job: $job_name"
    print_status "Press Ctrl+C to stop monitoring"

    while true; do
        local status=$(kubectl get rayjob "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.jobStatus}' 2>/dev/null || echo "NOT_FOUND")
        local deployment_status=$(kubectl get rayjob "$job_name" -n "$NAMESPACE" -o jsonpath='{.status.jobDeploymentStatus}' 2>/dev/null || echo "NOT_FOUND")

        echo "$(date '+%Y-%m-%d %H:%M:%S') - Job Status: $status | Deployment: $deployment_status"

        if [[ "$status" == "SUCCEEDED" ]]; then
            print_status "🎉 Job completed successfully!"
            break
        elif [[ "$status" == "FAILED" ]]; then
            print_error "❌ Job failed!"
            show_logs
            break
        elif [[ "$status" == "NOT_FOUND" ]]; then
            print_warning "Job not found yet..."
        fi

        sleep 10
    done
}


# Function to show dashboard access
show_dashboard() {
    print_header "Ray Dashboard Access"

    local service_name="spark-log-processor-head-svc"

    print_status "To access Ray Dashboard:"
    echo "1. Run: kubectl port-forward svc/$service_name 8265:8265 -n $NAMESPACE"
    echo "2. Open: http://localhost:8265"
    echo ""
    print_status "Or run this command now:"
    echo "kubectl port-forward svc/$service_name 8265:8265 -n $NAMESPACE"
}


# Function to cleanup temp files
cleanup_temp_files() {
    print_status "Cleaning up temporary files..."
    rm -f *.tmp *.bak 2>/dev/null || true
}


# Function to cleanup Ray job only
cleanup_rayjob() {
    print_header "Cleaning Up Ray Job Resources"

    read -p "Are you sure you want to delete the Ray job? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deleting Ray job..."
        kubectl delete rayjob spark-log-processing-job -n "$NAMESPACE" 2>/dev/null || true
        kubectl delete configmap spark-log-processor-code -n "$NAMESPACE" 2>/dev/null || true

        cleanup_temp_files
        print_status "✅ Ray job cleanup completed"
        print_status "💡 Terraform infrastructure preserved (namespace, IAM role, etc.)"
    else
        print_status "Cleanup cancelled"
    fi
}


# Function to verify Iceberg data
verify_data() {
    print_header "Verifying Ray Data Processing Results"

    # Check if Python and PyIceberg are available
    if ! command -v python3 &> /dev/null; then
        print_error "python3 is required for data verification"
        exit 1
    fi

    # Check if PyIceberg and dependencies are installed
    print_status "Checking PyIceberg and dependencies..."
    local missing_packages=()

    if ! python3 -c "import pyiceberg" 2>/dev/null; then
        missing_packages+=("pyiceberg[glue,s3fs]==0.7.0")
    fi

    if ! python3 -c "import numpy" 2>/dev/null; then
        missing_packages+=("numpy")
    fi

    if ! python3 -c "import pandas" 2>/dev/null; then
        missing_packages+=("pandas")
    fi

    if ! python3 -c "import pyarrow" 2>/dev/null; then
        missing_packages+=("pyarrow")
    fi

    if [ ${#missing_packages[@]} -gt 0 ]; then
        print_warning "Missing required packages: ${missing_packages[*]}"
        echo ""
        print_status "To install all required packages, run one of the following:"
        echo "  pip3 install 'pyiceberg[glue,s3fs]==0.7.0' numpy pandas pyarrow"
        echo "  python3 -m pip install 'pyiceberg[glue,s3fs]==0.7.0' numpy pandas pyarrow"
        echo ""

        # Check for available package managers
        local pip_cmd=""
        if command -v pip3 &> /dev/null; then
            pip_cmd="pip3"
        elif command -v pip &> /dev/null; then
            pip_cmd="pip"
        elif python3 -m pip --version &> /dev/null; then
            pip_cmd="python3 -m pip"
        fi

        if [[ -n "$pip_cmd" ]]; then
            read -p "Would you like to install PyIceberg now? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_status "Installing required packages using $pip_cmd..."
                if $pip_cmd install 'pyiceberg[glue,s3fs]==0.7.0' numpy pandas pyarrow; then
                    print_status "✅ All packages installed successfully"
                else
                    print_error "Failed to install required packages"
                    print_error "Please install manually using one of the commands above"
                    exit 1
                fi
            else
                print_status "Please install PyIceberg manually to use data verification"
                exit 1
            fi
        else
            print_error "No pip installation found"
            print_error "Please install pip first:"
            print_error "  - macOS: python3 -m ensurepip"
            print_error "  - Ubuntu/Debian: sudo apt-get install python3-pip"
            print_error "  - Or use your system's package manager"
            exit 1
        fi
    fi

    print_status "Creating verification script..."

    # Create inline Python verification script with parameters
    cat > verify_temp.py << EOF
#!/usr/bin/env python3
import sys
from pyiceberg.catalog import load_catalog

def verify_iceberg_data(aws_region, s3_bucket, iceberg_database, iceberg_table):
    """Query Iceberg table to verify Ray Data processing results"""

    warehouse_path = f"s3://{s3_bucket}/iceberg-warehouse/"

    try:
        print("🔍 Connecting to Iceberg catalog...")

        # Configure Glue catalog
        catalog = load_catalog(
            "glue",
            **{
                "type": "glue",
                "warehouse": warehouse_path,
                "region_name": aws_region
            }
        )

        # Load the table
        table_id = f"{iceberg_database}.{iceberg_table}"
        print(f"📊 Loading table: {table_id}")
        table = catalog.load_table(table_id)

        print(f"📂 Table location: {table.location()}")

        # Query the data using PyIceberg scan
        print("🎯 Querying Iceberg data...")

        # Get all data as PyArrow table
        scan = table.scan()
        arrow_table = scan.to_arrow()

        # Convert to Pandas for easier analysis
        df = arrow_table.to_pandas()

        print(f"\n✅ SUCCESS! Found {len(df)} records in Iceberg table")

        if len(df) == 0:
            print("⚠️  Warning: No data found in table")
            return True

        # Data verification and summary
        print("\n📋 Data Summary:")
        print(f"   📊 Total Records: {len(df)}")
        print(f"   📅 Date Range: {df['timestamp'].min()} to {df['timestamp'].max()}")
        print(f"   🏷️  Unique Apps: {df['spark_app_selector'].nunique()}")
        print(f"   📱 Unique Pods: {df['pod_name'].nunique()}")

        # Log level distribution
        print("\n📈 Log Level Distribution:")
        log_levels = df['log_level'].value_counts()
        for level, count in log_levels.items():
            print(f"   {level}: {count}")

        # Show sample records
        print("\n📝 Sample Records (First 3):")
        sample_df = df[['timestamp', 'log_level', 'pod_name', 'spark_app_selector', 'message']].head(3)
        for idx, row in sample_df.iterrows():
            print(f"   Record {idx + 1}:")
            print(f"     ⏰ Timestamp: {row['timestamp']}")
            print(f"     📊 Level: {row['log_level']}")
            print(f"     🏷️  App: {row['spark_app_selector']}")
            print(f"     📱 Pod: {row['pod_name']}")
            print(f"     💬 Message: {row['message'][:80]}...")
            print()

        # Data quality checks
        print("🔍 Data Quality Checks:")
        print(f"   ✅ No null timestamps: {df['timestamp'].notna().all()}")
        print(f"   ✅ No null log_levels: {df['log_level'].notna().all()}")
        print(f"   ✅ No null spark_app_selector: {df['spark_app_selector'].notna().all()}")

        # Spark app analysis
        spark_apps = df['spark_app_selector'].unique()
        print(f"\n🚀 Spark Applications Processed:")
        for app in spark_apps:
            app_count = len(df[df['spark_app_selector'] == app])
            print(f"   📱 {app}: {app_count} logs")

        return True

    except Exception as e:
        print(f"❌ Error querying Iceberg table: {e}")
        return False

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: python3 verify_temp.py <aws_region> <s3_bucket> <iceberg_database> <iceberg_table>")
        sys.exit(1)

    aws_region = sys.argv[1]
    s3_bucket = sys.argv[2]
    iceberg_database = sys.argv[3]
    iceberg_table = sys.argv[4]

    print("🔍 Verifying Ray Data processed logs in Iceberg...")
    success = verify_iceberg_data(aws_region, s3_bucket, iceberg_database, iceberg_table)

    if success:
        print("\n🎉 VERIFICATION SUCCESSFUL!")
        print("✅ Ray Data successfully processed and stored Spark logs in Iceberg format")
        print("✅ Data is accessible and queryable via PyIceberg")
        sys.exit(0)
    else:
        print("\n❌ VERIFICATION FAILED!")
        print("❌ Unable to access or query Iceberg data")
        sys.exit(1)
EOF

    print_status "Running PyIceberg verification..."

    # Run the verification script with parameters
    if python3 verify_temp.py "$AWS_REGION" "$S3_BUCKET" "$ICEBERG_DATABASE" "$ICEBERG_TABLE"; then
        print_status "✅ Data verification completed successfully"
    else
        print_error "❌ Data verification failed"
        print_error "Check that:"
        print_error "  - Ray job has completed successfully"
        print_error "  - PyIceberg is installed: pip install 'pyiceberg[glue,s3fs]'"
        print_error "  - AWS credentials are configured"
    fi

    # Cleanup
    rm -f verify_temp.py
}

# Function to show configuration summary
show_config() {
    print_header "Current Configuration"
    echo "AWS Region: $AWS_REGION"
    echo "Namespace: $NAMESPACE"
    echo "Iceberg Database: $ICEBERG_DATABASE"
    echo "Iceberg Table: $ICEBERG_TABLE"
    echo "Iceberg Warehouse: s3://$S3_BUCKET/iceberg-warehouse"
    echo "S3 Logs Path: s3://$S3_BUCKET/$S3_PREFIX"
    echo "Workers: $MIN_WORKERS-$MAX_WORKERS (initial: $INITIAL_WORKERS)"
    echo ""
}


# Main function
main() {
    case "${1:-deploy}" in
        "deploy")
            validate_prerequisites
            validate_config
            show_config
            update_yaml_files
            deploy_components
            cleanup_temp_files
            echo ""
            check_status
            echo ""
            show_dashboard
            echo ""
            print_status "🚀 Ray job deployment completed! Use '$0 monitor' to watch progress"
            ;;
        "status")
            check_status
            ;;
        "logs")
            show_logs
            ;;
        "monitor")
            monitor_job
            ;;
        "dashboard")
            show_dashboard
            ;;
        "cleanup")
            cleanup_rayjob
            ;;
        "config")
            show_config
            ;;
        "verify")
            verify_data
            ;;
        "help"|*)
            echo "Complete Ray Spark Log Processing with Iceberg - Deployment Script"
            echo ""
            echo "PREREQUISITES: Deploy Terraform module in parent EKS project first!"
            echo ""
            echo "Parent project structure:"
            echo "  your-eks-project/"
            echo "  ├── main.tf                 # Contains raydata_pipeline module"
            echo "  ├── raydata-pipeline/       # Ray Data Terraform module"
            echo "  └── examples/               # This script location"
            echo ""
            echo "Deploy module: terraform apply  # From parent project root"
            echo ""
            echo "Usage: $0 <command>"
            echo ""
            echo "Commands:"
            echo "  deploy     Deploy Ray job (requires Terraform module)"
            echo "  status     Check deployment status"
            echo "  logs       Show Ray job logs (follow mode)"
            echo "  monitor    Monitor job progress in real-time"
            echo "  dashboard  Show Ray dashboard access instructions"
            echo "  config     Show current configuration"
            echo "  verify     Verify processed data in Iceberg table"
            echo "  cleanup    Remove Ray job only (preserve infrastructure)"
            echo "  help       Show this help message"
            echo ""
            echo "Required configuration updates:"
            echo "  - S3_BUCKET: Replace <ENTER_S3_BUCKET> with your bucket name"
            echo ""
            echo "Features:"
            echo "  - Uses Apache Iceberg for ACID transactions"
            echo "  - AWS Glue catalog for metadata management"
            echo "  - Intelligent incremental processing"
            echo "  - Ray Data distributed processing"
            echo ""
            ;;
    esac
}


# Check configuration before deployment
if [[ "${1:-deploy}" == "deploy" ]]; then
    if [[ "$S3_BUCKET" == "<ENTER_S3_BUCKET>" ]]; then
        print_error "Please update the configuration section in this script before deployment!"
        echo ""
        echo "Required updates:"
        echo "  - S3_BUCKET: Replace <ENTER_S3_BUCKET> with your actual bucket name"
        echo ""
        echo "Example:"
        echo "  S3_BUCKET=\"my-spark-logs-bucket\""
        echo ""
        echo "Note: AWS credentials and Iceberg warehouse are automatically managed by Terraform."
        echo ""
        exit 1
    fi
fi


main "$@"
