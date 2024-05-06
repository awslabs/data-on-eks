import boto3
import json
from kafka import KafkaProducer
from kafka.errors import KafkaError
from kafka.admin import KafkaAdminClient, NewTopic
import socket
import time
import random
from kafka.errors import TopicAlreadyExistsError
import os

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
    return KafkaProducer(bootstrap_servers=bootstrap_brokers)

def produce_data(producer, topic_name):
    """Simulate and send random security detection data."""
    data_id = 1
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

    while True:
        alert_type = random.choice(alert_types)
        severity = random.choice(severities)
        description = random.choice(descriptions[alert_type])

        message = {
            'id': data_id,
            'timestamp': time.time(),
            'alert_type': alert_type,
            'severity': severity,
            'description': description
        }
        producer.send(topic_name, json.dumps(message).encode('utf-8'))
        print(f"Sent: {message}")
        data_id += 1
        time.sleep(random.uniform(0.5, 2))  # Randomize time between messages

if __name__ == '__main__':
    # Configuration
    topic_name = "security-topic"
    aws_region = os.getenv("AWS_REGION", "us-west-2")  # Replace with your AWS region
    num_partitions = 3
    replication_factor = 2
    bootstrap_brokers = os.getenv("BOOTSTRAP_BROKERS", 'b-1.kafkademospark.mkjcj4.c12.kafka.us-west-2.amazonaws.com:9092,b-2.kafkademospark.mkjcj4.c12.kafka.us-west-2.amazonaws.com:9092')
    print(bootstrap_brokers)
    create_topic(bootstrap_brokers, topic_name, num_partitions, replication_factor)
    producer = create_producer(bootstrap_brokers)
    try:
        produce_data(producer, topic_name)
    finally:
        producer.flush()
        producer.close()
