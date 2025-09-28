from pyflink.datastream import StreamExecutionEnvironment
from pyflink.table import StreamTableEnvironment, EnvironmentSettings
from models import CatInteraction, CatPopularity, SCHEMA_MAP, schema_to_flink_ddl
import os

def create_table_environment():
    """Create Flink table environment"""
    env = StreamExecutionEnvironment.get_execution_environment()
    env.set_parallelism(1)

    settings = EnvironmentSettings.new_instance().in_streaming_mode().build()
    table_env = StreamTableEnvironment.create(env, settings)

    # Add Kafka connector
    table_env.get_config().get_configuration().set_string(
        "pipeline.jars",
        "file:///opt/flink/lib/flink-sql-connector-kafka-4.0.1-2.0.jar"
    )

    return table_env

def create_source_table(table_env, kafka_servers):
    """Create Kafka source table for cat interactions"""
    schema = schema_to_flink_ddl(SCHEMA_MAP["cat_interactions"]["flink_schema"])

    ddl = f"""
    CREATE TABLE cat_interactions_source (
        {schema},
        proc_time AS PROCTIME()
    ) WITH (
        'connector' = 'kafka',
        'topic' = 'cat-interactions',
        'properties.bootstrap.servers' = '{kafka_servers}',
        'properties.group.id' = 'cat-popularity-consumer',
        'scan.startup.mode' = 'latest-offset',
        'format' = 'json'
    )
    """
    table_env.execute_sql(ddl)

def create_sink_table(table_env, kafka_servers):
    """Create Kafka sink table for cat popularity"""
    schema = schema_to_flink_ddl(SCHEMA_MAP["cat_popularity"]["flink_schema"])

    ddl = f"""
    CREATE TABLE cat_popularity_sink (
        {schema}
    ) WITH (
        'connector' = 'kafka',
        'topic' = 'cat-popularity',
        'properties.bootstrap.servers' = '{kafka_servers}',
        'format' = 'json'
    )
    """
    table_env.execute_sql(ddl)

def create_debug_table(table_env):
    """Create print sink table for local testing"""
    schema = schema_to_flink_ddl(SCHEMA_MAP["cat_popularity"]["flink_schema"])

    ddl = f"""
    CREATE TABLE cat_popularity_debug (
        {schema}
    ) WITH (
        'connector' = 'print',
        'print-identifier' = 'CAT-POPULARITY'
    )
    """
    table_env.execute_sql(ddl)

def main():
    # Configuration
    kafka_servers = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'localhost:9094')
    like_threshold = int(os.getenv('LIKE_THRESHOLD', '5'))

    print(f"Starting Cat Popularity job...")
    print(f"Kafka servers: {kafka_servers}")
    print(f"Like threshold: {like_threshold}")

    # Create environment and tables
    table_env = create_table_environment()
    create_source_table(table_env, kafka_servers)
    create_sink_table(table_env, kafka_servers)
    create_debug_table(table_env)

    # Main processing query - 5 minute sliding window counting likes per cat
    popularity_query = """
    INSERT INTO cat_popularity_sink
    SELECT
        cat_id,
        CAST(COUNT(*) AS INT) as like_count,
        UNIX_TIMESTAMP(CAST(window_start AS STRING)) * 1000 as window_start,
        UNIX_TIMESTAMP(CAST(window_end AS STRING)) * 1000 as window_end
    FROM TABLE(
        HOP(TABLE cat_interactions_source,
            DESCRIPTOR(ts),
            INTERVAL '1' MINUTE,
            INTERVAL '5' MINUTE)
    )
    WHERE interaction_type = 'like'
    GROUP BY cat_id, window_start, window_end
    HAVING COUNT(*) > 0
    """

    # Debug query - same logic but outputs to console
    debug_query = """
    INSERT INTO cat_popularity_debug
    SELECT
        cat_id,
        CAST(COUNT(*) AS INT) as like_count,
        UNIX_TIMESTAMP(CAST(window_start AS STRING)) * 1000 as window_start,
        UNIX_TIMESTAMP(CAST(window_end AS STRING)) * 1000 as window_end
    FROM TABLE(
        HOP(TABLE cat_interactions_source,
            DESCRIPTOR(ts),
            INTERVAL '10' SECOND,
            INTERVAL '20' SECOND)
    )
    WHERE interaction_type = 'like'
    GROUP BY cat_id, window_start, window_end
    HAVING COUNT(*) > 0
    """

    # Debug query - processing time windows
    debug_query = """
    INSERT INTO cat_popularity_debug
    SELECT
        cat_id,
        CAST(COUNT(*) AS INT) as like_count,
        UNIX_TIMESTAMP(CAST(window_start AS STRING)) * 1000 as window_start,
        UNIX_TIMESTAMP(CAST(window_end AS STRING)) * 1000 as window_end
    FROM TABLE(
        HOP(TABLE cat_interactions_source,
            DESCRIPTOR(proc_time),
            INTERVAL '5' SECOND,
            INTERVAL '10' SECOND)
    )
    WHERE interaction_type = 'like'
    GROUP BY cat_id, window_start, window_end
    HAVING COUNT(*) > 0
    """

    print("Executing processing time windowed query...")
    table_env.execute_sql(debug_query)

if __name__ == "__main__":
    main()
