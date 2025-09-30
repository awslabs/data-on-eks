import os
import re
from pyflink.datastream import StreamExecutionEnvironment
from pyflink.table import StreamTableEnvironment, EnvironmentSettings
from pyflink.table.expressions import col
from models import CatInteraction, CafeOrders, CatWellness, CatLocation, VisitorCheckIn, SCHEMA_MAP, schema_to_flink_ddl
import os

# ==============================================================================
#  1. Configuration
# ==============================================================================
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'cluster-kafka-brokers.kafka.svc:9092')
S3_WAREHOUSE_PATH = os.getenv('S3_WAREHOUSE_PATH', 's3a://your-bucket/iceberg-warehouse/')
ICEBERG_CATALOG_NAME = 'workshop'
GLUE_DATABASE_NAME = 'data_on_eks'

# ==============================================================================
#  2. Schema Definitions
# ==============================================================================

# Generate table configurations from models
def create_tables_config():
    config = {
        'cat_interactions': {
            'topic': 'cat-interactions',
            'model': SCHEMA_MAP["cat_interactions"]["class"],
            "schema": schema_to_flink_ddl(SCHEMA_MAP["cat_interactions"]["flink_schema"])
        },
        'visitor_checkins': {
            'topic': 'visitor-checkins',
            'model': SCHEMA_MAP["visitor_checkins"]["class"],
            "schema": schema_to_flink_ddl(SCHEMA_MAP["visitor_checkins"]["flink_schema"])
        },
        'cafe_orders': {
            'topic': 'cafe-orders',
            'model': SCHEMA_MAP["cafe_orders"]["class"],
            "schema": schema_to_flink_ddl(SCHEMA_MAP["cafe_orders"]["flink_schema"])
        },
        'cat_wellness': {
            'topic': 'cat-wellness-iot',
            'model': SCHEMA_MAP["cat_wellness"]["class"],
            "schema": schema_to_flink_ddl(SCHEMA_MAP["cat_wellness"]["flink_schema"])
        },
        'cat_locations': {
            'topic': 'cat-locations',
            'model': SCHEMA_MAP["cat_locations"]["class"],
            "schema": schema_to_flink_ddl(SCHEMA_MAP["cat_locations"]["flink_schema"])
        }
    }
}

# ==============================================================================
#  3. Helper Functions for Creating Tables
# ==============================================================================
def create_kafka_source_table(t_env, table_name, topic_name, schema_ddl):
    """Creates a unified Kafka source table in the default catalog."""
    t_env.execute_sql(f"""
        CREATE TABLE IF NOT EXISTS {table_name}_source (
            {schema_ddl},
            `event_ts` TIMESTAMP(3) METADATA FROM 'timestamp',
            WATERMARK FOR `event_ts` AS `event_ts` - INTERVAL '5' SECOND
        ) WITH (
            'connector' = 'kafka',
            'topic' = '{topic_name}',
            'properties.bootstrap.servers' = '{KAFKA_BOOTSTRAP_SERVERS}',
            'properties.group.id' = 'flink-raw-ingestion',
            'scan.startup.mode' = 'latest-offset',
            'format' = 'json'
        )
    """)

def create_iceberg_sink_table(t_env, table_name, schema_ddl, is_partitioned):
    """Creates a unified Iceberg sink table idempotently."""
    
    final_schema = schema_ddl
    partition_clause = ""
    target_table_name = f"{table_name}_raw"

    if is_partitioned:
        final_schema = f"{schema_ddl},\n            `event_date` DATE"
        partition_clause = "PARTITIONED BY (event_date)"
    
    t_env.execute_sql(f"""
        CREATE TABLE IF NOT EXISTS {target_table_name} (
            {final_schema}
        ) {partition_clause}
    """)

# ==============================================================================
#  4. Main Flink Job Logic
# ==============================================================================
def main():
    print("Starting Flink Raw Ingestion Job...")
    
    env = StreamExecutionEnvironment.get_execution_environment()
    env.set_parallelism(2)
    env.enable_checkpointing(120000)
    settings = EnvironmentSettings.new_instance().in_streaming_mode().build()
    t_env = StreamTableEnvironment.create(env, settings)

    # --- Step 1: Create all temporary Kafka source tables in the default catalog. ---
    print("--- Creating Kafka source tables in default catalog ---")
    for table_name, config in SCHEMA_DEFINITIONS.items():
        create_kafka_source_table(t_env, table_name, config['topic'], config['ddl'])
    print("--- Kafka source tables created successfully ---\n")

    # --- Step 2: Register the persistent Iceberg catalog. ---
    t_env.execute_sql(f"""
        CREATE CATALOG {ICEBERG_CATALOG_NAME} WITH (
            'type' = 'iceberg',
            'warehouse' = '{S3_WAREHOUSE_PATH}',
            'catalog-impl' = 'org.apache.iceberg.aws.glue.GlueCatalog',
            'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO'
        )
    """)
    
    # --- Step 3: Create all permanent Iceberg sink tables in the new catalog. ---
    print("--- Creating Iceberg sink tables in workshop catalog ---")
    for table_name, config in SCHEMA_DEFINITIONS.items():
        create_iceberg_sink_table(t_env, table_name, config['ddl'], config['is_partitioned'])
    print("--- Iceberg sink tables created successfully ---\n")

    # --- Step 4: Build and submit the INSERT statements. ---
    statement_set = t_env.create_statement_set()

    for table_name, config in SCHEMA_DEFINITIONS.items():
        print(f"--- Setting up pipeline for '{table_name}' ---")
        
        schema_ddl = config['ddl']
        is_partitioned = config['is_partitioned']
            
        field_pattern = r'`([^`]+)`'
        source_fields = re.findall(field_pattern, schema_ddl)
        
        target_table_name = f"{ICEBERG_CATALOG_NAME}.{GLUE_DATABASE_NAME}.{table_name}_raw"
        
        insert_sql = ""
        if is_partitioned:
            sink_fields = source_fields + ['event_date']
            select_fields = source_fields + ["CAST(TO_TIMESTAMP_LTZ(event_time, 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''') AS DATE)"]
            insert_sql = f"""
                INSERT INTO {target_table_name} ({', '.join(sink_fields)})
                SELECT {', '.join(select_fields)} FROM default_catalog.default_database.{table_name}_source
            """
        else:
            insert_sql = f"""
                INSERT INTO {target_table_name} ({', '.join(source_fields)})
                SELECT {', '.join(source_fields)} FROM default_catalog.default_database.{table_name}_source
            """
        
        print(f"{insert_sql}")
        statement_set.add_insert_sql(insert_sql)
        print(f"  > INSERT statement added to job.")

    print("\n=== EXECUTING FLINK JOB ===")
    statement_set.execute()
    print("Job submitted successfully.")

if __name__ == '__main__':
    main()
