from pyflink.datastream import StreamExecutionEnvironment
from pyflink.table import StreamTableEnvironment, EnvironmentSettings
from pyflink.table.expressions import col
import os

# Table configurations
TABLES_CONFIG = {
    'cat_interactions': {
        'topic': 'cat-interactions',
        'schema': """
            interaction_id STRING,
            cat_id STRING,
            visitor_id STRING,
            interaction_type STRING,
            duration_minutes INT,
            cat_stress_level INT,
            `timestamp` BIGINT,
            date_partition STRING
        """,
        'fields': ['interaction_id', 'cat_id', 'visitor_id', 'interaction_type', 'duration_minutes', 'cat_stress_level', '`timestamp`']
    },
    'adoption_events': {
        'topic': 'adoption-events',
        'schema': """
            event_id STRING,
            cat_id STRING,
            event_type STRING,
            visitor_id STRING,
            `timestamp` BIGINT,
            adoption_fee INT,
            weight_kg DECIMAL(4,2),
            coat_length STRING,
            coat_color STRING,
            age_months INT,
            favorite_food STRING,
            sociability_score INT,
            favorite_toy STRING,
            vocalization_level INT,
            date_partition STRING
        """,
        'fields': ['event_id', 'cat_id', 'event_type', 'visitor_id', '`timestamp`', 'adoption_fee', 'weight_kg', 'coat_length', 'coat_color', 'age_months', 'favorite_food', 'sociability_score', 'favorite_toy', 'vocalization_level']
    },
    'weight_readings': {
        'topic': 'cat-weight-readings',
        'schema': """
            reading_id STRING,
            cat_id STRING,
            weight_kg DECIMAL(4,2),
            scale_id STRING,
            `timestamp` BIGINT,
            date_partition STRING
        """,
        'fields': ['reading_id', 'cat_id', 'weight_kg', 'scale_id', '`timestamp`']
    },
    'revenue_events': {
        'topic': 'cafe-revenue',
        'schema': """
            transaction_id STRING,
            cat_id STRING,
            revenue_type STRING,
            amount DECIMAL(10,2),
            visitor_id STRING,
            `timestamp` BIGINT,
            date_partition STRING
        """,
        'fields': ['transaction_id', 'cat_id', 'revenue_type', 'amount', 'visitor_id', '`timestamp`']
    }
}

def get_field_type(field):
    """Map field names to their expected types"""
    int_fields = ['duration_minutes', 'cat_stress_level', 'adoption_fee', 'age_months', 'sociability_score', 'vocalization_level']
    decimal_fields = ['weight_kg', 'amount']
    
    field_clean = field.strip('`')
    if field_clean in int_fields:
        return 'INT'
    elif field_clean in decimal_fields:
        return 'DECIMAL(10,2)'
    elif field_clean == 'timestamp':
        return 'BIGINT'
    else:
        return 'STRING'

def create_kafka_source_table(table_env, table_name, topic_name):
    """Create Kafka source table"""
    kafka_servers = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'cluster-broker-0.cluster-kafka-brokers.kafka.svc:9092')
    
    ddl = f"""
    CREATE TABLE IF NOT EXISTS {table_name}_source (
        `data` STRING,
        `ts` TIMESTAMP(3) METADATA FROM 'timestamp',
        WATERMARK FOR `ts` AS `ts` - INTERVAL '5' SECOND
    ) WITH (
        'connector' = 'kafka',
        'topic' = '{topic_name}',
        'properties.bootstrap.servers' = '{kafka_servers}',
        'properties.group.id' = 'flink-workshop',
        'scan.startup.mode' = 'latest-offset',
        'format' = 'raw'
    )
    """
    table_env.execute_sql(ddl)

def create_iceberg_sink_table(table_env, table_name, schema_ddl):
    """Create Iceberg sink table"""
    s3_warehouse = os.getenv('S3_WAREHOUSE_PATH', 's3a://your-bucket/iceberg-warehouse/')
    
    ddl = f"""
    CREATE TABLE IF NOT EXISTS {table_name}_sink (
        {schema_ddl}
    ) WITH (
        'connector' = 'iceberg',
        'catalog-name' = 's3_catalog',
        'catalog-type' = 'hadoop',
        'warehouse' = '{s3_warehouse}',
        'format-version' = '2'
    )
    """
    table_env.execute_sql(ddl)

def create_debug_table(table_env, table_name, schema_ddl):
    """Create debug print table if enabled"""
    ddl = f"""
    CREATE TABLE IF NOT EXISTS {table_name}_debug (
        {schema_ddl}
    ) WITH (
        'connector' = 'print',
        'print-identifier' = 'DEBUG-{table_name}'
    )
    """
    table_env.execute_sql(ddl)

def main():

    env = StreamExecutionEnvironment.get_execution_environment()
    env.set_parallelism(2)
    env.enable_checkpointing(120000)  # 2 minutes
    
    settings = EnvironmentSettings.new_instance().in_streaming_mode().build()
    table_env = StreamTableEnvironment.create(env, settings)
    
    # Register Iceberg catalog
    s3_warehouse = os.getenv('S3_WAREHOUSE_PATH', 's3a://your-bucket/iceberg-warehouse/')
    table_env.execute_sql(f"""
        CREATE CATALOG s3_catalog WITH (
            'type' = 'iceberg',
            'warehouse' = '{s3_warehouse}',
            'catalog-impl' = 'org.apache.iceberg.hadoop.HadoopCatalog'
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
        create_kafka_source_table(table_env, table_name, config['topic'])
        create_iceberg_sink_table(table_env, table_name, config['schema'])
        
        # Create debug table if enabled
        if debug_enabled:
            create_debug_table(table_env, table_name, config['schema'])
        
        # Build JSON field extraction with error handling
        json_fields = []
        for field in config['fields']:
            field_type = get_field_type(field)
            field_clean = field.strip('`')
            json_fields.append(f"CAST(JSON_VALUE(`data`, '$.{field_clean}') AS {field_type}) AS {field}")
        
        json_fields_str = ',\n        '.join(json_fields)
        
        # Create INSERT statement for Iceberg sink
        insert_sql = f"""
        INSERT INTO {table_name}_sink
        SELECT 
            {json_fields_str},
            DATE_FORMAT(FROM_UNIXTIME(CAST(JSON_VALUE(`data`, '$.timestamp') AS BIGINT) / 1000), 'yyyy-MM-dd') AS date_partition
        FROM {table_name}_source
        WHERE JSON_VALUE(`data`, '$.timestamp') IS NOT NULL
        """
        
        statement_set.add_insert_sql(insert_sql)
        print(f"Added {table_name} to Iceberg sink")
        
        # Add debug insert if enabled
        if debug_enabled:
            debug_sql = f"""
            INSERT INTO {table_name}_debug
            SELECT 
                {json_fields_str},
                DATE_FORMAT(FROM_UNIXTIME(CAST(JSON_VALUE(`data`, '$.timestamp') AS BIGINT) / 1000), 'yyyy-MM-dd') AS date_partition
            FROM {table_name}_source
            WHERE JSON_VALUE(`data`, '$.timestamp') IS NOT NULL
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
