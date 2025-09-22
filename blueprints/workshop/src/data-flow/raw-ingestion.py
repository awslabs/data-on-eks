from pyflink.datastream import StreamExecutionEnvironment
from pyflink.table import StreamTableEnvironment, EnvironmentSettings
from pyflink.table.expressions import col
import os

def get_schema_for_table(table_name):
    """Get schema DDL for each table"""
    schemas = {
        'cat_interactions': """
            interaction_id STRING,
            cat_id STRING,
            visitor_id STRING,
            interaction_type STRING,
            duration_minutes INT,
            cat_stress_level INT,
            `timestamp` BIGINT,
            date_partition STRING
        """,
        'adoption_events': """
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
        'weight_readings': """
            reading_id STRING,
            cat_id STRING,
            weight_kg DECIMAL(4,2),
            scale_id STRING,
            `timestamp` BIGINT,
            date_partition STRING
        """,
        'revenue_events': """
            transaction_id STRING,
            cat_id STRING,
            revenue_type STRING,
            amount DECIMAL(10,2),
            visitor_id STRING,
            `timestamp` BIGINT,
            date_partition STRING
        """
    }
    return schemas.get(table_name, "")

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
        'scan.startup.mode' = 'earliest-offset',
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

def main():
    # Environment setup
    env = StreamExecutionEnvironment.get_execution_environment()
    env.set_parallelism(2)
    env.enable_checkpointing(120000)  # 2 minutes
    
    settings = EnvironmentSettings.new_instance().in_streaming_mode().build()
    table_env = StreamTableEnvironment.create(env, settings)
    
    # Iceberg connector should be pre-loaded in the container
    
    # Cat Interactions
    create_kafka_source_table(table_env, 'cat_interactions', 'cat-interactions')
    create_iceberg_sink_table(table_env, 'cat_interactions', """
        interaction_id STRING,
        cat_id STRING,
        visitor_id STRING,
        interaction_type STRING,
        duration_minutes INT,
        cat_stress_level INT,
        `timestamp` BIGINT,
        date_partition STRING
    """)
    
    # Adoption Events  
    create_kafka_source_table(table_env, 'adoption_events', 'adoption-events')
    create_iceberg_sink_table(table_env, 'adoption_events', """
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
    """)
    
    # Weight Readings
    create_kafka_source_table(table_env, 'weight_readings', 'cat-weight-readings')
    create_iceberg_sink_table(table_env, 'weight_readings', """
        reading_id STRING,
        cat_id STRING,
        weight_kg DECIMAL(4,2),
        scale_id STRING,
        `timestamp` BIGINT,
        date_partition STRING
    """)
    
    # Revenue Events
    create_kafka_source_table(table_env, 'revenue_events', 'cafe-revenue')
    create_iceberg_sink_table(table_env, 'revenue_events', """
        transaction_id STRING,
        cat_id STRING,
        revenue_type STRING,
        amount DECIMAL(10,2),
        visitor_id STRING,
        `timestamp` BIGINT,
        date_partition STRING
    """)
    
    # Insert statements with JSON parsing and date partitioning
    tables = [
        ('cat_interactions', ['interaction_id', 'cat_id', 'visitor_id', 'interaction_type', 'duration_minutes', 'cat_stress_level', '`timestamp`']),
        ('adoption_events', ['event_id', 'cat_id', 'event_type', 'visitor_id', '`timestamp`', 'adoption_fee', 'weight_kg', 'coat_length', 'coat_color', 'age_months', 'favorite_food', 'sociability_score', 'favorite_toy', 'vocalization_level']),
        ('weight_readings', ['reading_id', 'cat_id', 'weight_kg', 'scale_id', '`timestamp`']),
        ('revenue_events', ['transaction_id', 'cat_id', 'revenue_type', 'amount', 'visitor_id', '`timestamp`'])
    ]
    
    # Test with just one table first
    table_name = 'cat_interactions'
    fields = ['interaction_id', 'cat_id', 'visitor_id', 'interaction_type', 'duration_minutes', 'cat_stress_level', '`timestamp`']
    
    print(f"Creating source table for {table_name}")
    create_kafka_source_table(table_env, table_name, 'cat-interactions')
    
    print(f"Creating sink table for {table_name}")
    create_iceberg_sink_table(table_env, table_name, get_schema_for_table(table_name))
    
    print("Tables created successfully")
    
    # Create a print sink for debugging
    print_ddl = f"""
    CREATE TABLE IF NOT EXISTS {table_name}_debug (
        {get_schema_for_table(table_name)}
    ) WITH (
        'connector' = 'print',
        'print-identifier' = 'DEBUG-{table_name}'
    )
    """
    table_env.execute_sql(print_ddl)
    
    # Create INSERT statement with logging
    json_fields = ', '.join([
        f"CAST(JSON_VALUE(`data`, '$.{field.strip('`')}') AS {get_field_type(field)}) AS {field}" 
        for field in fields
    ])
    
    insert_sql = f"""
    INSERT INTO {table_name}_sink
    SELECT 
        {json_fields},
        DATE_FORMAT(FROM_UNIXTIME(CAST(JSON_VALUE(`data`, '$.timestamp') AS BIGINT) / 1000), 'yyyy-MM-dd') AS date_partition
    FROM {table_name}_source
    """
    
    # Also insert into debug table
    debug_sql = f"""
    INSERT INTO {table_name}_debug
    SELECT 
        {json_fields},
        DATE_FORMAT(FROM_UNIXTIME(CAST(JSON_VALUE(`data`, '$.timestamp') AS BIGINT) / 1000), 'yyyy-MM-dd') AS date_partition
    FROM {table_name}_source
    """
    
    print("=== INSERT SQL ===")
    print(insert_sql)
    print("=== STARTING EXECUTION ===")
    
    # Execute with statement set for better logging
    statement_set = table_env.create_statement_set()
    statement_set.add_insert_sql(insert_sql)
    statement_set.add_insert_sql(debug_sql)
    
    print("Executing INSERT statement")
    result = statement_set.execute()
    print("Flink job started successfully - check TaskManager logs for data processing")

if __name__ == '__main__':
    main()
