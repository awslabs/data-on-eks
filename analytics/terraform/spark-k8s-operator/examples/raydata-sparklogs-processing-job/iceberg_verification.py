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
