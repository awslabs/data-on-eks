#!/usr/bin/env python3
"""
Clickstream Metrics Consumer
Consumes aggregated metrics from Kafka and displays them
"""

import json
from kafka import KafkaConsumer
from datetime import datetime

# Configuration
KAFKA_BOOTSTRAP_SERVERS = ['data-on-eks-kafka-bootstrap:9092']
TOPIC_NAME = 'clickstream-metrics'


class MetricsConsumer:
    def __init__(self):
        self.consumer = KafkaConsumer(
            TOPIC_NAME,
            bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
            auto_offset_reset='latest',
            enable_auto_commit=True,
            group_id='metrics-consumer-group',
            value_deserializer=lambda m: json.loads(m.decode('utf-8'))
        )
        print(f"✓ Connected to Kafka: {KAFKA_BOOTSTRAP_SERVERS}")
        print(f"✓ Consuming from topic: {TOPIC_NAME}")
        print(f"✓ Consumer group: metrics-consumer-group\n")

    def format_metrics(self, metrics):
        """Format metrics for display"""
        output = []
        output.append("\n" + "="*80)
        output.append(f"📊 CLICKSTREAM METRICS")
        output.append("="*80)
        output.append(f"⏰ Window: {metrics['window_start']} → {metrics['window_end']}")
        output.append("")

        # Overall stats
        output.append("📈 OVERVIEW:")
        output.append(f"   Total Events:     {metrics['total_events']:,}")
        output.append(f"   Unique Users:     {metrics['unique_users']:,}")
        output.append(f"   Unique Sessions:  {metrics['unique_sessions']:,}")
        output.append(f"   Avg Duration:     {metrics['avg_duration_ms']:,}ms")
        output.append("")

        # Event types
        output.append("🔹 EVENT TYPES:")
        for event_type, count in sorted(metrics['event_types'].items(), key=lambda x: x[1], reverse=True):
            percentage = (count / metrics['total_events']) * 100
            output.append(f"   {event_type:15s} {count:6,} ({percentage:5.1f}%)")
        output.append("")

        # Devices
        output.append("📱 DEVICES:")
        for device, count in sorted(metrics['devices'].items(), key=lambda x: x[1], reverse=True):
            percentage = (count / metrics['total_events']) * 100
            output.append(f"   {device:15s} {count:6,} ({percentage:5.1f}%)")
        output.append("")

        # Top referrers
        output.append("🔗 TOP REFERRERS:")
        for referrer, count in metrics['top_referrers'].items():
            percentage = (count / metrics['total_events']) * 100
            output.append(f"   {referrer:20s} {count:6,} ({percentage:5.1f}%)")
        output.append("")

        # Top pages
        output.append("📄 TOP PAGES:")
        for page, count in metrics['top_pages'].items():
            percentage = (count / metrics['total_events']) * 100
            output.append(f"   {page:30s} {count:6,} ({percentage:5.1f}%)")
        output.append("")

        output.append("="*80)

        return "\n".join(output)

    def run(self):
        """Consume and display metrics"""
        print("🚀 Starting metrics consumer...")
        print("⏱️  Waiting for metrics (Ctrl+C to stop)\n")

        count = 0
        try:
            for message in self.consumer:
                count += 1
                metrics = message.value

                # Display formatted metrics
                print(self.format_metrics(metrics))

                # Log metadata
                print(f"📍 Partition: {message.partition} | Offset: {message.offset} | "
                      f"Total consumed: {count}\n")

        except KeyboardInterrupt:
            print("\n⚠️  Interrupted by user")
        finally:
            print(f"\n✅ Total metrics consumed: {count}")
            self.consumer.close()
            print("✓ Consumer closed")


if __name__ == '__main__':
    consumer = MetricsConsumer()
    consumer.run()
