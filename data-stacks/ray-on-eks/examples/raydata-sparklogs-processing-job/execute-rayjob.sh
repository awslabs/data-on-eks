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
S3_BUCKET="${S3_BUCKET:-}"  # Will use exported environment variable
S3_PREFIX="${CLUSTER_NAME}/spark-application-logs/spark-team-a" # Will use exported CLUSTER_NAME
AWS_REGION="${AWS_REGION:-}" # Will use exported environment variable

NAMESPACE="raydata"

# Iceberg Configuration
ICEBERG_CATALOG_TYPE="glue"
ICEBERG_DATABASE="raydata_spark_logs"
ICEBERG_TABLE="spark_logs"

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

    if [[ -z "$S3_BUCKET" ]]; then
        print_error "S3_BUCKET environment variable is not set"
        print_error "Please export S3_BUCKET with your actual S3 bucket name"
        print_error "Example: export S3_BUCKET=\"my-spark-logs-bucket\""
        errors=$((errors + 1))
    fi

    if [[ -z "$CLUSTER_NAME" ]]; then
        print_error "CLUSTER_NAME environment variable is not set"
        print_error "Please export CLUSTER_NAME with your actual cluster name"
        print_error "Example: export CLUSTER_NAME=\"my-eks-cluster\""
        errors=$((errors + 1))
    fi

    if [[ -z "$AWS_REGION" ]]; then
        print_error "AWS_REGION environment variable is not set"
        print_error "Please export AWS_REGION with your AWS region"
        print_error "Example: export AWS_REGION=\"us-west-2\""
        errors=$((errors + 1))
    fi

    if [[ $errors -gt 0 ]]; then
        print_error "Please set the required environment variables"
        exit 1
    fi

    print_status "✅ Configuration validation passed"
    print_status "✅ Using S3 bucket: $S3_BUCKET"
    print_status "✅ Using cluster: $CLUSTER_NAME"
    print_status "✅ Using region: $AWS_REGION"
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

# Function to show configuration summary
show_config() {
    print_header "Current Configuration"
    echo "AWS Region: $AWS_REGION"
    echo "Cluster Name: $CLUSTER_NAME"
    echo "S3 Bucket: $S3_BUCKET"
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
        "help"|*)
            echo "Complete Ray Spark Log Processing with Iceberg - Deployment Script"
            echo ""
            echo "PREREQUISITES: Deploy Terraform module in parent EKS project first!"
            echo ""
            echo "Required Environment Variables:"
            echo "  export S3_BUCKET=\"your-bucket-name\""
            echo "  export CLUSTER_NAME=\"your-cluster-name\""
            echo "  export AWS_REGION=\"your-region\""
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
            echo "  cleanup    Remove Ray job only (preserve infrastructure)"
            echo "  help       Show this help message"
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

main "$@"