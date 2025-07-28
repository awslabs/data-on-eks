#!/bin/bash

# Ray Data Iceberg Verification Script
# This script creates a Python virtual environment and verifies Ray Data processed logs in Iceberg

set -euo pipefail

#---------------------------------------------------------------
# Configuration Variables
#---------------------------------------------------------------
S3_BUCKET=<S3_BUCKET>                 # Replace with your S3 bucket name
# replace with your AWS region                 # Iceberg table name
AWS_REGION=<AWS_REGION>
ICEBERG_DATABASE="raydata_spark_logs"          # Glue database name
ICEBERG_TABLE="spark_logs"
                       # AWS region

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

    if [[ "$S3_BUCKET" == "<S3_BUCKET>" ]]; then
        print_error "Please update S3_BUCKET in the script with your actual bucket name"
        exit 1
    fi

    print_success "Configuration validated"
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

    # Run the verification script
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
# Main Execution
#---------------------------------------------------------------
main() {
    print_header "Ray Data Iceberg Verification Tool"
    echo "This script verifies that Ray Data has successfully processed Spark logs into Iceberg format"
    echo ""

    validate_config
    check_prerequisites
    setup_venv
    run_verification

    print_success "Verification completed successfully!"
}

# Run main function
main "$@"
