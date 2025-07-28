#!/bin/bash

# Ray Data Iceberg Verification Script
# This script creates a Python virtual environment and verifies Ray Data processed logs in Iceberg

set -euo pipefail

#---------------------------------------------------------------
# Configuration Variables
#---------------------------------------------------------------
S3_BUCKET="<ENTER_S3_BUCKET>"                  # Replace with your S3 bucket name
ICEBERG_DATABASE="raydata_spark_logs"            # Glue database name
ICEBERG_TABLE="spark_logs"                       # Iceberg table name
AWS_REGION="us-west-2"                           # AWS region

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
    
    if [[ "$S3_BUCKET" == "<ENTER_S3_BUCKET>" ]]; then
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
# Verification Script
#---------------------------------------------------------------
create_verification_script() {
    print_header "Creating Verification Script"
    
    cat > iceberg_verification.py << 'EOF'
#!/usr/bin/env python3
"""
Ray Data Iceberg Verification Script
Connects to Iceberg catalog and verifies processed Spark logs
"""

import sys
import os
from datetime import datetime
from pyiceberg.catalog import load_catalog
import pandas as pd

def verify_iceberg_data(aws_region, s3_bucket, iceberg_database, iceberg_table):
    """Query Iceberg table to verify Ray Data processing results"""
    
    warehouse_path = f"s3://{s3_bucket}/iceberg-warehouse/"
    
    try:
        print("🔍 Connecting to Iceberg catalog...")
        
        # Configure Iceberg catalog
        catalog = load_catalog(
            name="default",
            **{
                "type": "glue",
                "property-version": "1",
                "warehouse": warehouse_path,
                "glue.region": aws_region
            }
        )
        
        print(f"✅ Connected to Iceberg catalog in region: {aws_region}")
        
        # Load the table
        print(f"📊 Loading table: {iceberg_database}.{iceberg_table}")
        table = catalog.load_table(f"{iceberg_database}.{iceberg_table}")
        
        print("✅ Table loaded successfully")
        
        # Get table schema
        print("\n📋 Table Schema:")
        schema = table.schema()
        for field in schema.fields:
            field_type = str(field.field_type).replace('iceberg.types.', '')
            required = "required" if field.required else "optional"
            print(f"  - {field.name}: {field_type} ({required})")
        
        # Scan the table and get basic statistics
        print("\n🔍 Scanning table data...")
        scan = table.scan()
        df = scan.to_pandas()
        
        if df.empty:
            print("❌ No data found in Iceberg table")
            return False
        
        total_records = len(df)
        print(f"✅ SUCCESS! Found {total_records} records in Iceberg table")
        
        # Data analysis
        print("\n📋 Data Summary:")
        print(f"   📊 Total Records: {total_records}")
        
        if 'timestamp' in df.columns:
            df['timestamp'] = pd.to_datetime(df['timestamp'])
            min_time = df['timestamp'].min()
            max_time = df['timestamp'].max()
            print(f"   📅 Date Range: {min_time} to {max_time}")
        
        if 'application_id' in df.columns:
            unique_apps = df['application_id'].nunique()
            print(f"   🏷️ Unique Apps: {unique_apps}")
        
        if 'pod_name' in df.columns:
            unique_pods = df['pod_name'].nunique()
            print(f"   📱 Unique Pods: {unique_pods}")
        
        if 'log_level' in df.columns:
            print("\n📈 Log Level Distribution:")
            log_level_counts = df['log_level'].value_counts()
            for level, count in log_level_counts.items():
                print(f"   {level}: {count}")
        
        # Sample data
        print("\n📝 Sample Records:")
        sample_df = df.head(3)
        for idx, row in sample_df.iterrows():
            print(f"\n  Record {idx + 1}:")
            for col in ['timestamp', 'log_level', 'component', 'message']:
                if col in row:
                    value = str(row[col])[:100] + "..." if len(str(row[col])) > 100 else str(row[col])
                    print(f"    {col}: {value}")
        
        return True
        
    except Exception as e:
        print(f"❌ Error during verification: {e}")
        return False

def main():
    if len(sys.argv) != 5:
        print("Usage: python3 iceberg_verification.py <aws_region> <s3_bucket> <iceberg_database> <iceberg_table>")
        sys.exit(1)
    
    aws_region = sys.argv[1]
    s3_bucket = sys.argv[2]
    iceberg_database = sys.argv[3]
    iceberg_table = sys.argv[4]
    
    print("🔍 Verifying Ray Data processed logs in Iceberg...")
    print(f"   🌍 Region: {aws_region}")
    print(f"   🪣 S3 Bucket: {s3_bucket}")
    print(f"   🗃️ Database: {iceberg_database}")
    print(f"   📊 Table: {iceberg_table}")
    print()
    
    success = verify_iceberg_data(aws_region, s3_bucket, iceberg_database, iceberg_table)
    
    if success:
        print("\n🎉 VERIFICATION SUCCESSFUL!")
        print("✅ Ray Data successfully processed and stored Spark logs in Iceberg format")
        print("✅ Data is accessible and queryable via PyIceberg")
        print("✅ You can now query this data using Amazon Athena or other SQL tools")
    else:
        print("\n❌ VERIFICATION FAILED!")
        print("Check that:")
        print("  - Ray job has been deployed and completed successfully")
        print("  - AWS credentials have proper permissions for Glue and S3")
        print("  - The specified database and table exist in AWS Glue")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    print_success "Verification script created"
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
    
    # Remove temporary files
    if [[ -f "iceberg_verification.py" ]]; then
        rm -f iceberg_verification.py
        print_info "Removed verification script"
    fi
    
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
    create_verification_script
    run_verification
    
    print_success "Verification completed successfully!"
}

# Run main function
main "$@"