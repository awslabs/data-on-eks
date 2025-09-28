import json
import argparse
from kafka import KafkaConsumer

# Topic names
TOPIC_CAT_INTERACTIONS = 'cat-interactions'
TOPIC_ADOPTION_EVENTS = 'adoption-events'
TOPIC_WEIGHT_READINGS = 'cat-weight-readings'
TOPIC_CAFE_REVENUE = 'cafe-revenue'

ALL_TOPICS = [
    TOPIC_CAT_INTERACTIONS,
    TOPIC_ADOPTION_EVENTS,
    TOPIC_WEIGHT_READINGS,
    TOPIC_CAFE_REVENUE
]

def main():
    parser = argparse.ArgumentParser(description='Cat Cafe Test Consumer')
    parser.add_argument(
        '--bootstrap-servers',
        default='localhost:9094',
        help='Kafka bootstrap servers (default: localhost:9094)'
    )

    args = parser.parse_args()

    consumer = KafkaConsumer(
        *ALL_TOPICS,
        bootstrap_servers=[args.bootstrap_servers],
        value_deserializer=lambda m: json.loads(m.decode('utf-8')),
        group_id='test-consumer-group',
        auto_offset_reset='latest'
    )

    print(f"Test consumer started, listening to topics: {', '.join(ALL_TOPICS)}")
    print("Press Ctrl+C to stop\n")

    try:
        for message in consumer:
            topic = message.topic
            value = message.value

            if topic == TOPIC_CAT_INTERACTIONS:
                print(f"[INTERACTIONS] {value['interaction_type']} | Cat: {value['cat_id']} | Visitor: {value['visitor_id']} | Duration: {value['duration_minutes']}min | Stress: {value['cat_stress_level']}")

            elif topic == TOPIC_ADOPTION_EVENTS:
                print(f"[ADOPTION] {value['event_type']} | Cat: {value['cat_id']} | Visitor: {value['visitor_id']} | Fee: ${value['adoption_fee']/100:.2f} | Color: {value['coat_color']} | Age: {value['age_months']}mo")

            elif topic == TOPIC_WEIGHT_READINGS:
                print(f"[WEIGHT] Cat: {value['cat_id']} | Weight: {value['weight_kg']}kg | Scale: {value['scale_id']}")

            elif topic == TOPIC_CAFE_REVENUE:
                cat_info = f" | Cat: {value['cat_id']}" if value['cat_id'] else ""
                print(f"[REVENUE] {value['revenue_type']} | Amount: ${value['amount']:.2f} | Visitor: {value['visitor_id']}{cat_info}")

    except KeyboardInterrupt:
        print("\nShutting down consumer...")
    finally:
        consumer.close()

if __name__ == "__main__":
    main()
