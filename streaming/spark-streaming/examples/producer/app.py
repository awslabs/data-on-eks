import boto3
import json
from kafka import KafkaProducer
from kafka.admin import KafkaAdminClient, NewTopic
from kafka.errors import KafkaError, TopicAlreadyExistsError
from concurrent.futures import ThreadPoolExecutor, as_completed
import time
import random
import os
import threading

def create_topic(bootstrap_servers, topic_name, num_partitions, replication_factor):
    """Create a Kafka topic."""
    client = KafkaAdminClient(bootstrap_servers=bootstrap_servers)
    topic_list = [NewTopic(name=topic_name, num_partitions=num_partitions, replication_factor=replication_factor)]
    try:
        client.create_topics(new_topics=topic_list, validate_only=False)
        print(f"Topic {topic_name} created successfully.")
    except TopicAlreadyExistsError:
        print(f"Topic {topic_name} already exists.")
    except Exception as e:
        print(f"Failed to create topic {topic_name}: {e}")

def create_producer(bootstrap_brokers):
    """Create a Kafka producer."""
    return KafkaProducer(
        bootstrap_servers=bootstrap_brokers,
        linger_ms=10,  # Add some delay to batch messages
        batch_size=32768,  # Adjust batch size
        buffer_memory=33554432  # Increase buffer memory
    )

def generate_random_alert(data_id, alert_types, severities, descriptions):
    """Generate a random alert message."""
    alert_type = random.choice(alert_types)
    severity = random.choice(severities)
    description = random.choice(descriptions[alert_type])

    return {
        'id': data_id,
        'timestamp': time.time(),
        'alert_type': alert_type,
        'severity': severity,
        'description': description
    }

def produce_data(producer, topic_name, rate_per_second, num_messages=1000, num_threads=4):
    """Produce data at a specified rate per second."""
    alert_types = ['intrusion', 'data leak', 'malware', 'phishing', 'ransomware']
    severities = ['low', 'medium', 'high', 'critical']

    descriptions = {
        'intrusion': [
            'Unauthorized access detected.',
            'Suspicious login attempt blocked.',
            'Possible brute force attack detected.'
        ],
        'data leak': [
            'Sensitive data exposed to public.',
            'Unauthorized data access from multiple locations.',
            'Data exfiltration attempt detected.'
        ],
        'malware': [
            'Malware detected on endpoint.',
            'Ransomware infection attempt blocked.',
            'Suspicious file download intercepted.'
        ],
        'phishing': [
            'Phishing email detected in user inbox.',
            'Credential phishing attempt identified.',
            'Suspicious domain communication intercepted.'
        ],
        'ransomware': [
            'Ransomware encryption behavior detected.',
            'Host isolated due to ransomware threat.',
            'Suspicious encryption of files noticed.'
        ]
    }

    def produce_batch(batch_id, num_batches, rate_limiter):
        for i in range(batch_id * num_batches, (batch_id + 1) * num_batches):
            rate_limiter.acquire()  # Wait for permission to send
            message = generate_random_alert(i, alert_types, severities, descriptions)
            try:
                producer.send(topic_name, json.dumps(message).encode('utf-8'))
                print(f"Sent: {message}")
            except KafkaError as e:
                print(f"Failed to send message: {e}")
        producer.flush()

    num_batches_per_thread = num_messages // num_threads
    rate_limiter = threading.Semaphore(rate_per_second)

    def refill_semaphore():
        while True:
            time.sleep(1)
            for _ in range(rate_per_second):
                rate_limiter.release()

    # Start a background thread to refill the rate limiter semaphore
    threading.Thread(target=refill_semaphore, daemon=True).start()

    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        futures = [executor.submit(produce_batch, thread_id, num_batches_per_thread, rate_limiter) for thread_id in range(num_threads)]
        for future in as_completed(futures):
            future.result()

if __name__ == '__main__':
    # Configuration
    topic_name = "security-topic"
    aws_region = os.getenv("AWS_REGION", "us-west-2")  # Replace with your AWS region
    num_partitions = 3
    replication_factor = 2
    bootstrap_brokers = os.getenv("BOOTSTRAP_BROKERS", 'b-1.kafkademospark.mkjcj4.c12.kafka.us-west-2.amazonaws.com:9092,b-2.kafkademospark.mkjcj4.c12.kafka.us-west-2.amazonaws.com:9092')
    rate_per_second = int(os.getenv("RATE_PER_SECOND", 100000))
    num_messages = int(os.getenv("NUM_OF_MESSAGES", 10000000))
    num_threads = 8

    # Create Kafka topic if it doesn't exist
    create_topic(bootstrap_brokers, topic_name, num_partitions, replication_factor)

    # Create Kafka producer
    producer = create_producer(bootstrap_brokers)

    # Produce data with rate limiting
    try:
        produce_data(producer, topic_name, rate_per_second=rate_per_second, num_messages=num_messages, num_threads=num_threads)  # Adjust `rate_per_second` as needed
    finally:
        producer.close()
