import asyncio
import json
import random
import time
import uuid
from datetime import datetime
from kafka import KafkaProducer

# Configuration
KAFKA_BOOTSTRAP_SERVERS = ['localhost:9094']

# Sample data
INTERACTION_TYPES = ['pet', 'play', 'feed', 'photo']
COAT_COLORS = ['tabby', 'calico', 'black', 'orange', 'gray', 'white']
COAT_LENGTHS = ['short', 'medium', 'long']
FAVORITE_FOODS = ['salmon', 'chicken', 'tuna', 'beef', 'turkey']
FAVORITE_TOYS = ['feather', 'ball', 'laser', 'catnip', 'string']
EVENT_TYPES = ['inquiry', 'application', 'adoption', 'return']
REVENUE_TYPES = ['adoption_fee', 'cafe_visit', 'merchandise', 'photo_session']

def create_producer():
    """Create a Kafka producer"""
    return KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        key_serializer=lambda k: k.encode('utf-8') if k else None,
        request_timeout_ms=10000,
        metadata_max_age_ms=10000
    )

async def produce_cat_interactions(producer):
    """Produce cat interaction events"""
    while True:
        event = {
            "interaction_id": str(uuid.uuid4()),
            "cat_id": f"cat_{random.randint(1, 100):03d}",
            "visitor_id": f"visitor_{random.randint(1, 500):03d}",
            "interaction_type": random.choice(INTERACTION_TYPES),
            "duration_minutes": random.randint(1, 30),
            "cat_stress_level": random.randint(1, 10),
            "timestamp": int(datetime.now().timestamp() * 1000)
        }
        
        producer.send('cat-interactions', key=event['interaction_id'], value=event)
        print(f"[INTERACTIONS] {event['interaction_type']} for cat {event['cat_id']} (stress: {event['cat_stress_level']})")
        
        await asyncio.sleep(random.uniform(0.5, 3))

async def produce_adoption_events(producer):
    """Produce adoption events"""
    while True:
        event = {
            "event_id": str(uuid.uuid4()),
            "cat_id": f"cat_{random.randint(1, 100):03d}",
            "event_type": random.choice(EVENT_TYPES),
            "visitor_id": f"visitor_{random.randint(1, 500):03d}",
            "timestamp": int(datetime.now().timestamp() * 1000),
            "adoption_fee": random.randint(5000, 25000),
            "weight_kg": round(random.uniform(2.5, 8.0), 2),
            "coat_length": random.choice(COAT_LENGTHS),
            "coat_color": random.choice(COAT_COLORS),
            "age_months": random.randint(2, 120),
            "favorite_food": random.choice(FAVORITE_FOODS),
            "sociability_score": random.randint(1, 10),
            "favorite_toy": random.choice(FAVORITE_TOYS),
            "vocalization_level": random.randint(1, 10)
        }
        
        producer.send('adoption-events', key=event['event_id'], value=event)
        print(f"[ADOPTION] {event['event_type']} for cat {event['cat_id']}")
        
        await asyncio.sleep(random.uniform(1, 5))

async def produce_weight_readings(producer):
    """Produce weight readings"""
    while True:
        event = {
            "reading_id": str(uuid.uuid4()),
            "cat_id": f"cat_{random.randint(1, 100):03d}",
            "weight_kg": round(random.uniform(2.0, 9.0), 2),
            "scale_id": f"scale_{random.randint(1, 5):02d}",
            "timestamp": int(datetime.now().timestamp() * 1000)
        }
        
        producer.send('cat-weight-readings', key=event['reading_id'], value=event)
        print(f"[WEIGHT] Cat {event['cat_id']} - {event['weight_kg']}kg")
        
        await asyncio.sleep(random.uniform(5, 15))

async def produce_revenue_events(producer):
    """Produce revenue events"""
    while True:
        revenue_type = random.choice(REVENUE_TYPES)
        
        if revenue_type == 'adoption_fee':
            amount = round(random.uniform(50.00, 250.00), 2)
            cat_id = f"cat_{random.randint(1, 100):03d}"
        elif revenue_type == 'cafe_visit':
            amount = round(random.uniform(15.00, 45.00), 2)
            cat_id = f"cat_{random.randint(1, 100):03d}" if random.random() > 0.3 else None
        elif revenue_type == 'merchandise':
            amount = round(random.uniform(10.00, 75.00), 2)
            cat_id = f"cat_{random.randint(1, 100):03d}" if random.random() > 0.5 else None
        else:  # photo_session
            amount = round(random.uniform(20.00, 60.00), 2)
            cat_id = f"cat_{random.randint(1, 100):03d}"
        
        event = {
            "transaction_id": str(uuid.uuid4()),
            "cat_id": cat_id,
            "revenue_type": revenue_type,
            "amount": amount,
            "visitor_id": f"visitor_{random.randint(1, 500):03d}",
            "timestamp": int(datetime.now().timestamp() * 1000)
        }
        
        producer.send('cafe-revenue', key=event['transaction_id'], value=event)
        cat_info = f" for cat {event['cat_id']}" if event['cat_id'] else ""
        print(f"[REVENUE] ${event['amount']:.2f} {event['revenue_type']}{cat_info}")
        
        await asyncio.sleep(random.uniform(2, 8))

async def main():
    producer = create_producer()
    print("Starting all Cat Cafe data producers...")
    
    try:
        # Run all producers concurrently
        await asyncio.gather(
            produce_cat_interactions(producer),
            produce_adoption_events(producer),
            produce_weight_readings(producer),
            produce_revenue_events(producer)
        )
    except KeyboardInterrupt:
        print("\nShutting down all producers...")
    finally:
        producer.close()

if __name__ == "__main__":
    asyncio.run(main())
