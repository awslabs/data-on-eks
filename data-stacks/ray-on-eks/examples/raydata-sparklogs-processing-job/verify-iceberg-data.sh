#!/bin/bash

# Ray Data Iceberg Verification Script
# This script creates a Python virtual environment and verifies Ray Data processed logs in Iceberg

# How to execute
# export S3_BUCKET="spark-on-eks-spark-logs-123456789"
# export AWS_REGION="us-west-2"
# ./verify-iceberg-data.sh

set -euo pipefail

#---------------------------------------------------------------
# Configuration Variables
#---------------------------------------------------------------
S3_BUCKET="${S3_BUCKET:-}"                     # Uses environment variable
AWS_REGION="${AWS_REGION:-}"                   # Uses environment variable
ICEBERG_DATABASE="raydata_spark_logs"          # Glue database name
ICEBERG_TABLE="spark_logs"                     # Iceberg table name

#---------------------------------------------------------------
# Colors for output
#---------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#---------------------------------------------------------------
# Print functions
#---------------------------------------------------------------
print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_header() {
    echo -e "${BLUE}==== $1 ====${NC}"
}

#---------------------------------------------------------------
# Validation Functions
#---------------------------------------------------------------
validate_config() {
    print_header "Validating Configuration"

    local errors=0

    if [[ -z "$S3_BUCKET" ]]; then
        print_error "S3_BUCKET environment variable is not set"
        print_error "Please export S3_BUCKET with your actual S3 bucket name"
        print_error "Example: export S3_BUCKET=\"my-spark-logs-bucket\""
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

    print_success "Configuration validated"
    print_info "Using S3 bucket: $S3_BUCKET"
    print_info "Using AWS region: $AWS_REGION"
    print_info "Iceberg database: $ICEBERG_DATABASE"
    print_info "Iceberg table: $ICEBERG_TABLE"
}

check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check if Python 3 is installed
    if ! command -v python3 &> /dev/null; then
        print_error "python3 is required but not installed"
        exit 1
    fi

    # Check if pip is installed
    if ! command -v pip3 &> /dev/null; then
        print_error "pip3 is required but not installed"
        exit 1
    fi

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is required but not installed"
        exit 1
    fi

    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured. Run 'aws configure' first"
        exit 1
    fi

    print_success "All prerequisites are available"
}

#---------------------------------------------------------------
# Virtual Environment Management
#---------------------------------------------------------------
setup_venv() {
    print_header "Setting up Python Virtual Environment"

    local venv_dir="raydata-verification-venv"

    # Remove existing venv if it exists
    if [[ -d "$venv_dir" ]]; then
        print_info "Removing existing virtual environment..."
        rm -rf "$venv_dir"
    fi

    # Create new virtual environment
    print_info "Creating Python virtual environment..."
    python3 -m venv "$venv_dir"

    # Activate virtual environment
    print_info "Activating virtual environment..."
    source "$venv_dir/bin/activate"

    # Upgrade pip
    print_info "Upgrading pip..."
    pip install --upgrade pip

    # Install PyIceberg with required extras
    print_info "Installing PyIceberg and dependencies..."
    pip install 'pyiceberg[glue,s3fs]==0.7.0' numpy pandas pyarrow boto3

    print_success "Virtual environment setup completed"

    # Export venv directory for cleanup
    export VENV_DIR="$venv_dir"
}

#---------------------------------------------------------------
# Main Verification Function
#---------------------------------------------------------------
run_verification() {
    print_header "Running Iceberg Data Verification"

    # Activate virtual environment
    source "$VENV_DIR/bin/activate"

    # Check if verification script exists
    if [[ ! -f "iceberg_verification.py" ]]; then
        print_error "iceberg_verification.py not found in current directory"
        print_error "Please ensure the verification Python script is present"
        exit 1
    fi

    # Run the verification script
    print_info "Running verification with parameters:"
    print_info "  AWS Region: $AWS_REGION"
    print_info "  S3 Bucket: $S3_BUCKET"
    print_info "  Database: $ICEBERG_DATABASE"
    print_info "  Table: $ICEBERG_TABLE"

    python3 iceberg_verification.py "$AWS_REGION" "$S3_BUCKET" "$ICEBERG_DATABASE" "$ICEBERG_TABLE"
}

#---------------------------------------------------------------
# Cleanup Function
#---------------------------------------------------------------
cleanup() {
    print_header "Cleaning Up"

    # Remove virtual environment
    if [[ -n "${VENV_DIR:-}" ]] && [[ -d "$VENV_DIR" ]]; then
        rm -rf "$VENV_DIR"
        print_info "Removed virtual environment"
    fi

    print_success "Cleanup completed"
}

#---------------------------------------------------------------
# Signal handling for cleanup
#---------------------------------------------------------------
trap cleanup EXIT INT TERM

#---------------------------------------------------------------
# Help Function
#---------------------------------------------------------------
show_help() {
    echo "Ray Data Iceberg Verification Tool"
    echo ""
    echo "This script verifies that Ray Data has successfully processed Spark logs into Iceberg format"
    echo ""
    echo "Required Environment Variables:"
    echo "  export S3_BUCKET=\"your-bucket-name\""
    echo "  export AWS_REGION=\"your-region\""
    echo ""
    echo "Usage: $0 [help]"
    echo ""
    echo "Prerequisites:"
    echo "  - Python 3 with pip"
    echo "  - AWS CLI configured with credentials"
    echo "  - iceberg_verification.py in current directory"
    echo ""
    echo "The script will:"
    echo "  1. Validate configuration and prerequisites"
    echo "  2. Create a Python virtual environment"
    echo "  3. Install PyIceberg and dependencies"
    echo "  4. Run verification against Iceberg table"
    echo "  5. Clean up virtual environment"
}

#---------------------------------------------------------------
# Main Execution
#---------------------------------------------------------------
main() {
    case "${1:-run}" in
        "help"|"-h"|"--help")
            show_help
            exit 0
            ;;
        *)
            print_header "Ray Data Iceberg Verification Tool"
            echo "This script verifies that Ray Data has successfully processed Spark logs into Iceberg format"
            echo ""

            validate_config
            check_prerequisites
            setup_venv
            run_verification

            print_success "Verification completed successfully!"
            ;;
    esac
}

# Run main function
main "$@"