#!/usr/bin/env python3
"""
Clickstream Event Producer
Generates realistic clickstream events and sends them to Kafka
"""

import json
import random
import time
from datetime import datetime
from kafka import KafkaProducer
import uuid

# Configuration
KAFKA_BOOTSTRAP_SERVERS = ['data-on-eks-kafka-bootstrap:9092']
TOPIC_NAME = 'clickstream-events'

# Sample data for realistic events
PAGES = [
    '/home', '/products', '/products/laptop', '/products/phone',
    '/products/tablet', '/cart', '/checkout', '/about', '/contact',
    '/blog', '/search', '/account', '/wishlist'
]

CATEGORIES = ['electronics', 'home', 'fashion', 'sports', 'books']
REFERRERS = ['google.com', 'x.com', 'reddit.com', 'direct', 'email']
DEVICES = ['mobile', 'desktop', 'tablet']
COUNTRIES = ['US', 'UK', 'CA', 'DE', 'FR', 'JP', 'AU']
EVENT_TYPES = ['page_view', 'click', 'add_to_cart', 'purchase', 'search']

class ClickstreamProducer:
    def __init__(self):
        self.producer = KafkaProducer(
            bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            key_serializer=lambda k: k.encode('utf-8') if k else None
        )
        print(f"✓ Connected to Kafka: {KAFKA_BOOTSTRAP_SERVERS}")
        print(f"✓ Producing to topic: {TOPIC_NAME}\n")

    def generate_event(self, user_id, session_id):
        """Generate a single clickstream event"""
        event = {
            'event_id': str(uuid.uuid4()),
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'user_id': user_id,
            'session_id': session_id,
            'event_type': random.choice(EVENT_TYPES),
            'page_url': random.choice(PAGES),
            'page_category': random.choice(CATEGORIES),
            'referrer': random.choice(REFERRERS),
            'device_type': random.choice(DEVICES),
            'country': random.choice(COUNTRIES),
            'duration_ms': random.randint(500, 10000)
        }
        return event

    def send_event(self, event):
        """Send event to Kafka"""
        # Use user_id as key for partitioning
        key = event['user_id']

        future = self.producer.send(TOPIC_NAME, key=key, value=event)
        # Wait for confirmation
        record_metadata = future.get(timeout=10)

        return record_metadata

    def run(self, events_per_second=10, duration_seconds=None):
        """
        Generate and send clickstream events

        Args:
            events_per_second: Rate of event generation
            duration_seconds: How long to run (None = infinite)
        """
        print(f"🚀 Generating {events_per_second} events/second")
        if duration_seconds:
            print(f"⏱️  Running for {duration_seconds} seconds\n")
        else:
            print("⏱️  Running indefinitely (Ctrl+C to stop)\n")

        count = 0
        start_time = time.time()

        # Simulate multiple users and sessions
        num_users = 100
        sessions = {}

        try:
            while True:
                batch_start = time.time()

                # Generate events for this second
                for _ in range(events_per_second):
                    # Pick a random user
                    user_id = f"user_{random.randint(1, num_users)}"

                    # Each user has a session (20% chance to start new session)
                    if user_id not in sessions or random.random() < 0.2:
                        sessions[user_id] = f"sess_{uuid.uuid4().hex[:12]}"

                    session_id = sessions[user_id]

                    # Generate and send event
                    event = self.generate_event(user_id, session_id)
                    metadata = self.send_event(event)

                    count += 1

                    if count % 50 == 0:
                        elapsed = time.time() - start_time
                        rate = count / elapsed if elapsed > 0 else 0
                        print(f"📊 Sent {count} events | Rate: {rate:.1f} events/sec | "
                              f"Partition: {metadata.partition} | Offset: {metadata.offset}")

                # Check if we should stop
                if duration_seconds and (time.time() - start_time) >= duration_seconds:
                    break

                # Sleep to maintain desired rate
                batch_duration = time.time() - batch_start
                sleep_time = max(0, 1.0 - batch_duration)
                time.sleep(sleep_time)

        except KeyboardInterrupt:
            print("\n⚠️  Interrupted by user")
        finally:
            elapsed = time.time() - start_time
            avg_rate = count / elapsed if elapsed > 0 else 0
            print(f"\n✅ Summary:")
            print(f"   Total events: {count}")
            print(f"   Duration: {elapsed:.1f}s")
            print(f"   Average rate: {avg_rate:.1f} events/sec")
            self.producer.flush()
            self.producer.close()
            print("✓ Producer closed")

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Clickstream Event Producer')
    parser.add_argument('--rate', type=int, default=10,
                        help='Events per second (default: 10)')
    parser.add_argument('--duration', type=int, default=None,
                        help='Duration in seconds (default: infinite)')

    args = parser.parse_args()

    producer = ClickstreamProducer()
    producer.run(events_per_second=args.rate, duration_seconds=args.duration)
