from pyflink.datastream import StreamExecutionEnvironment
from pyflink.table import StreamTableEnvironment, EnvironmentSettings
from pyflink.table.expressions import col
from models import CatInteraction, AdoptionEvent, CatWeightReading, CafeRevenue, SCHEMA_MAP, schema_to_flink_ddl
import os



# Generate table configurations from models
def create_tables_config():
    config = {
        'cat_interactions': {
            'topic': 'cat-interactions',
            'model': SCHEMA_MAP["cat_interactions"]["class"],
            "schema": schema_to_flink_ddl(SCHEMA_MAP["cat_interactions"]["flink_schema"])
        },
        'adoption_events': {
            'topic': 'adoption-events',
            'model': SCHEMA_MAP["adoption_events"]["class"],
            "schema": schema_to_flink_ddl(SCHEMA_MAP["adoption_events"]["flink_schema"])
        },
        'weight_readings': {
            'topic': 'weight-readings',
            'model': SCHEMA_MAP["weight_readings"]["class"],
            "schema": schema_to_flink_ddl(SCHEMA_MAP["weight_readings"]["flink_schema"])
        },
        'cafe_revenues': {
            'topic': 'cafe-revenues',
            'model': SCHEMA_MAP["cafe_revenues"]["class"],
            "schema": schema_to_flink_ddl(SCHEMA_MAP["cafe_revenues"]["flink_schema"])
        }
    }

    return config

def create_kafka_source_table(table_env, table_name, topic_name, schema):
    """Create Kafka source table"""
    kafka_servers = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'cluster-broker-0.cluster-kafka-brokers.kafka.svc:9092')

    ddl = f"""
    CREATE TABLE IF NOT EXISTS {table_name}_source (
        {schema},
        `event_ts` TIMESTAMP(3) METADATA FROM 'timestamp',
        WATERMARK FOR `event_ts` AS `event_ts` - INTERVAL '5' SECOND
    ) WITH (
        'connector' = 'kafka',
        'topic' = '{topic_name}',
        'properties.bootstrap.servers' = '{kafka_servers}',
        'properties.group.id' = 'flink-workshop',
        'scan.startup.mode' = 'latest-offset',
        'format' = 'json'
    )
    """
    table_env.execute_sql(ddl)

def create_iceberg_sink_table(table_env, table_name, schema):
    """Create Iceberg sink table"""
    s3_warehouse = os.getenv('S3_WAREHOUSE_PATH', 's3a://your-bucket/iceberg-warehouse/')

    ddl = f"""
    CREATE TABLE IF NOT EXISTS {table_name}_raw (
        {schema}
    ) WITH (
        'connector' = 'iceberg',
        'catalog-name' = 'workshop',
        'catalog-type' = 'hadoop',
        'warehouse' = '{s3_warehouse}',
        'format-version' = '2'
    )
    """
    table_env.execute_sql(ddl)

def create_debug_table(table_env, table_name, schema):
    """Create debug print table if enabled"""
    ddl = f"""
    CREATE TABLE IF NOT EXISTS {table_name}_debug (
        {schema}
    ) WITH (
        'connector' = 'print',
        'print-identifier' = 'DEBUG-{table_name}'
    )
    """
    table_env.execute_sql(ddl)

def main():

    TABLES_CONFIG = create_tables_config()

    env = StreamExecutionEnvironment.get_execution_environment()
    env.set_parallelism(2)
    env.enable_checkpointing(120000)  # 2 minutes

    settings = EnvironmentSettings.new_instance().in_streaming_mode().build()
    table_env = StreamTableEnvironment.create(env, settings)

    # Register Iceberg catalog with Glue
    s3_warehouse = os.getenv('S3_WAREHOUSE_PATH', 's3a://your-bucket/iceberg-warehouse/')
    table_env.execute_sql(f"""
        CREATE CATALOG workshop WITH (
            'type' = 'iceberg',
            'warehouse' = '{s3_warehouse}',
            'catalog-impl'='org.apache.iceberg.aws.glue.GlueCatalog',
            'io-impl' = 'org.apache.iceberg.aws.s3.S3FileIO',
            'glue.database' = 'data-on-eks'
        )
    """)

    debug_enabled = os.getenv('WORKSHOP_DEBUG', 'false').lower() == 'true'
    print(f"Debug mode: {'enabled' if debug_enabled else 'disabled'}")

    # Create statement set for batch execution
    statement_set = table_env.create_statement_set()

    # Process all tables
    for table_name, config in TABLES_CONFIG.items():
        print(f"Setting up {table_name}...")

        # Create source and sink tables
        create_kafka_source_table(table_env, table_name, config['topic'], config['schema'])
        create_iceberg_sink_table(table_env, table_name, config['schema'])

        # Create debug table if enabled
        if debug_enabled:
            create_debug_table(table_env, table_name, config['schema'])

        # Get field names from schema
        schema_dict = SCHEMA_MAP[table_name]["flink_schema"]
        field_names = list(schema_dict.keys())

        # Create INSERT statement for Iceberg sink
        insert_sql = f"""
        INSERT INTO {table_name}_raw
        SELECT {', '.join(field_names)}
        FROM {table_name}_source
        """

        statement_set.add_insert_sql(insert_sql)
        print(f"Added {table_name} to Iceberg sink")

        # Add debug insert if enabled
        if debug_enabled:
            debug_sql = f"""
            INSERT INTO {table_name}_debug
            SELECT {', '.join(field_names)}
            FROM {table_name}_source
            """
            statement_set.add_insert_sql(debug_sql)
            print(f"Added {table_name} to debug output")

    print("=== STARTING EXECUTION ===")
    print(f"Processing {len(TABLES_CONFIG)} tables: {', '.join(TABLES_CONFIG.keys())}")

    # Execute all statements
    result = statement_set.execute()
    print("Flink job started successfully - check TaskManager logs for data processing")

if __name__ == '__main__':
    main()
