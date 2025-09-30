import os
from pyflink.datastream import StreamExecutionEnvironment
from pyflink.table import StreamTableEnvironment, EnvironmentSettings
from models import SCHEMA_MAP, schema_to_flink_ddl

# It's good practice to centralize configuration
KAFKA_BOOTSTRAP_SERVERS = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'cluster-kafka-brokers.kafka.svc:9092')
S3_WAREHOUSE_PATH = os.getenv('S3_WAREHOUSE_PATH', 's3a://your-bucket/iceberg-warehouse/')
DEBUG_ENABLED = os.getenv('WORKSHOP_DEBUG', 'false').lower() == 'true'

def create_kafka_source_table(t_env: StreamTableEnvironment, table_name: str, topic_name: str, schema_ddl: str):
    """Creates a Kafka source table with a watermark."""
    # Using TO_TIMESTAMP to properly handle string-based event times
    ddl = f"""
    CREATE TABLE IF NOT EXISTS {table_name}_source (
        {schema_ddl},
        `event_ts` AS TO_TIMESTAMP_LTZ(event_time, 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''),
        WATERMARK FOR `event_ts` AS `event_ts` - INTERVAL '5' SECOND
    ) WITH (
        'connector' = 'kafka',
        'topic' = '{topic_name}',
        'properties.bootstrap.servers' = '{KAFKA_BOOTSTRAP_SERVERS}',
        'properties.group.id' = 'flink-alerting-jobs',
        'scan.startup.mode' = 'latest-offset',
        'format' = 'json'
    )
    """
    t_env.execute_sql(ddl)

def create_upsert_kafka_sink_table(t_env: StreamTableEnvironment, table_name: str, topic_name: str, schema_ddl: str):
    """Creates an upsert Kafka sink table for handling updates."""
    ddl = f"""
    CREATE TABLE IF NOT EXISTS {table_name}_sink (
        {schema_ddl}
    ) WITH (
        'connector' = 'upsert-kafka',
        'topic' = '{topic_name}',
        'properties.bootstrap.servers' = '{KAFKA_BOOTSTRAP_SERVERS}',
        'key.format' = 'json',
        'value.format' = 'json'
    )
    """
    t_env.execute_sql(ddl)

def create_kafka_sink_table(t_env: StreamTableEnvironment, table_name: str, topic_name: str, schema_ddl: str):
    """Creates a Kafka sink table."""
    ddl = f"""
    CREATE TABLE IF NOT EXISTS {table_name}_sink (
        {schema_ddl}
    ) WITH (
        'connector' = 'kafka',
        'topic' = '{topic_name}',
        'properties.bootstrap.servers' = '{KAFKA_BOOTSTRAP_SERVERS}',
        'format' = 'json'
    )
    """
    t_env.execute_sql(ddl)
    
def create_debug_sink(t_env: StreamTableEnvironment, table_name: str, schema_ddl: str):
    """Creates a print sink for debugging purposes."""
    ddl = f"""
    CREATE TABLE IF NOT EXISTS {table_name}_debug_sink (
        {schema_ddl}
    ) WITH (
        'connector' = 'print',
        'print-identifier' = 'ALERT-{table_name}'
    )
    """
    t_env.execute_sql(ddl)

def define_cat_wellness_alerts(t_env: StreamTableEnvironment):
    """
    Defines the Flink SQL job for the Cat Wellness Guardian.
    This is a stateless job that filters for anomalies.
    """
    print("Defining Cat Wellness Guardian job...")
    
    # 1. Define Source Table (from cat-wellness-iot topic)
    source_schema = schema_to_flink_ddl(SCHEMA_MAP["cat_wellness"]["flink_schema"])
    create_kafka_source_table(t_env, "cat_wellness", "cat-wellness-iot", source_schema)
    
    # 2. Define Sink Table (to cat-health-alerts topic)
    sink_schema = """
        `alert_time` TIMESTAMP(3),
        `cat_id` STRING,
        `alert_type` STRING,
        `value` DOUBLE,
        `threshold` DOUBLE,
        `alert_message` STRING
    """
    create_kafka_sink_table(t_env, "cat_health_alerts", "cat-health-alerts", sink_schema)
    if DEBUG_ENABLED:
        create_debug_sink(t_env, "cat_health_alerts", sink_schema)

    # 3. Define the INSERT logic
    # We create a simple view to make the final UNION cleaner
    t_env.execute_sql("""
        CREATE TEMPORARY VIEW DehydrationAlerts AS
        SELECT
            event_ts AS alert_time,
            cat_id,
            'DEHYDRATION' AS alert_type,
            hours_since_last_drink AS `value`,
            4.0 AS threshold,
            'Health Alert for ' || cat_id || ': Hours since last drink (' || CAST(hours_since_last_drink AS STRING) || ') exceeds threshold (4.0).' AS alert_message
        FROM cat_wellness_source
        WHERE hours_since_last_drink > 4.0
    """)

    t_env.execute_sql("""
        CREATE TEMPORARY VIEW StressAlerts AS
        SELECT
            event_ts AS alert_time,
            cat_id,
            'STRESS' AS alert_type,
            activity_level AS `value`,
            0.1 AS threshold,
            'Health Alert for ' || cat_id || ': Activity level (' || CAST(activity_level AS STRING) || ') is below threshold (0.1).' AS alert_message
        FROM cat_wellness_source
        WHERE activity_level < 0.1
    """)

    # Use a StatementSet to combine multiple INSERT statements
    statement_set = t_env.create_statement_set()
    
    insert_sql = """
        INSERT INTO cat_health_alerts_sink
        SELECT * FROM DehydrationAlerts
        UNION ALL
        SELECT * FROM StressAlerts
    """
    statement_set.add_insert_sql(insert_sql)
    
    if DEBUG_ENABLED:
        debug_insert_sql = """
            INSERT INTO cat_health_alerts_debug_sink
            SELECT * FROM DehydrationAlerts
            UNION ALL
            SELECT * FROM StressAlerts
        """
        statement_set.add_insert_sql(debug_insert_sql)

def define_potential_adopter_alerts(t_env: StreamTableEnvironment, statement_set):
    """
    Defines the Flink SQL job for the Adopter Detective.
    This is a stateful job that aggregates interaction data.
    """
    print("Defining Adopter Detective job...")
    
    # 1. Define Source Table (from cat-interactions topic)
    source_schema = schema_to_flink_ddl(SCHEMA_MAP["cat_interactions"]["flink_schema"])
    create_kafka_source_table(t_env, "cat_interactions", "cat-interactions", source_schema)
    
    # 2. Define Sink Table (to potential-adopters topic)
    sink_schema = """
        `visitor_id` STRING,
        `alert_time` TIMESTAMP(3),
        `liked_cats` STRING,
        `number_of_likes` BIGINT,
        `alert_message` STRING,
        PRIMARY KEY (visitor_id) NOT ENFORCED
    """
    create_upsert_kafka_sink_table(t_env, "potential_adopters", "potential-adopters", sink_schema)
    if DEBUG_ENABLED:
        create_debug_sink(t_env, "potential_adopters", sink_schema)

    # 3. Define the INSERT logic
    # This query performs a continuous aggregation.
    # It will emit a new result every time a visitor's like count changes and meets the condition.
    t_env.execute_sql("""
        CREATE TEMPORARY VIEW LikedInteractions AS
        SELECT
            visitor_id,
            cat_id,
            event_ts
        FROM cat_interactions_source
        WHERE interaction_type = 'like'
    """)

    # This view performs the stateful aggregation
    t_env.execute_sql("""
        CREATE TEMPORARY VIEW AdopterCandidates AS
        SELECT
            visitor_id,
            COUNT(DISTINCT cat_id) AS number_of_likes,
            LISTAGG(DISTINCT cat_id, ', ') AS liked_cats,
            MAX(event_ts) as last_like_time
        FROM LikedInteractions
        GROUP BY visitor_id
    """)

    # Final selection and formatting for the alert
    insert_sql = """
        INSERT INTO potential_adopters_sink
        SELECT
            visitor_id,
            last_like_time AS alert_time,
            liked_cats,
            number_of_likes,
            'Potential adopter detected: ' || visitor_id || ' has liked ' || CAST(number_of_likes AS STRING) || ' cats.' AS alert_message
        FROM AdopterCandidates
        WHERE number_of_likes > 3
    """
    statement_set.add_insert_sql(insert_sql)
    
    if DEBUG_ENABLED:
        debug_insert_sql = """
            INSERT INTO potential_adopters_debug_sink
            SELECT
                visitor_id,
                last_like_time AS alert_time,
                liked_cats,
                number_of_likes,
                'Potential adopter detected: ' || visitor_id || ' has liked ' || CAST(number_of_likes AS STRING) || ' cats.' AS alert_message
            FROM AdopterCandidates
            WHERE number_of_likes > 3
        """
        statement_set.add_insert_sql(debug_insert_sql)

def main():
    # Set up the Flink execution environment
    env = StreamExecutionEnvironment.get_execution_environment()
    env.set_parallelism(2)
    env.enable_checkpointing(120000) # Checkpoint every 2 minutes

    settings = EnvironmentSettings.new_instance().in_streaming_mode().build()
    t_env = StreamTableEnvironment.create(env, settings)
    
    # Create statement set for all jobs
    statement_set = t_env.create_statement_set()

    # Define the alerting pipelines
    define_cat_wellness_alerts(t_env)
    define_potential_adopter_alerts(t_env, statement_set)

    # Execute the combined job
    print("=== EXECUTING ALERTING JOBS ===")
    statement_set.execute()
    print("Flink jobs started successfully.")


if __name__ == '__main__':
    main()

