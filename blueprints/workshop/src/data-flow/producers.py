import asyncio
import json
import random
import time
import uuid
from datetime import datetime
from decimal import Decimal
from kafka import KafkaProducer
from models import CatInteraction, AdoptionEvent, CatWeightReading, CafeRevenue
from cat_profiles import get_random_cat_id, get_cat_profile, get_realistic_weight, get_realistic_stress_level

# Topic names
TOPIC_CAT_INTERACTIONS = 'cat-interactions'
TOPIC_ADOPTION_EVENTS = 'adoption-events'
TOPIC_WEIGHT_READINGS = 'cat-weight-readings'
TOPIC_CAFE_REVENUE = 'cafe-revenue'

# Sample data
INTERACTION_TYPES = ['pet', 'play', 'feed', 'photo']
EVENT_TYPES = ['inquiry', 'application', 'adoption', 'return']
REVENUE_TYPES = ['adoption_fee', 'cafe_visit', 'merchandise', 'photo_session']

def serialize_event(event):
    """Convert dataclass to JSON-serializable dict"""
    if hasattr(event, '__dict__'):
        data = {}
        for key, value in event.__dict__.items():
            if isinstance(value, Decimal):
                data[key] = float(value)
            else:
                data[key] = value
        return data
    return event

def create_producer(bootstrap_servers):
    """Create a Kafka producer"""
    return KafkaProducer(
        bootstrap_servers=bootstrap_servers,
        value_serializer=lambda v: json.dumps(serialize_event(v)).encode('utf-8'),
        key_serializer=lambda k: k.encode('utf-8') if k else None,
        request_timeout_ms=10000,
        metadata_max_age_ms=10000
    )

async def produce_cat_interactions(producer):
    """Produce cat interaction events"""
    while True:
        cat_id = get_random_cat_id()
        
        event = CatInteraction(
            interaction_id=str(uuid.uuid4()),
            cat_id=cat_id,
            visitor_id=f"visitor_{random.randint(1, 500):03d}",
            interaction_type=random.choice(INTERACTION_TYPES),
            duration_minutes=random.randint(1, 30),
            cat_stress_level=get_realistic_stress_level(cat_id),
            timestamp=int(datetime.now().timestamp() * 1000)
        )
        
        producer.send(TOPIC_CAT_INTERACTIONS, key=event.interaction_id, value=event)
        print(f"[INTERACTIONS] {event.interaction_type} for cat {event.cat_id} (stress: {event.cat_stress_level})")
        
        await asyncio.sleep(random.uniform(0.5, 3))

async def produce_adoption_events(producer):
    """Produce adoption events"""
    while True:
        cat_id = get_random_cat_id()
        profile = get_cat_profile(cat_id)
        
        event = AdoptionEvent(
            event_id=str(uuid.uuid4()),
            cat_id=cat_id,
            event_type=random.choice(EVENT_TYPES),
            visitor_id=f"visitor_{random.randint(1, 500):03d}",
            timestamp=int(datetime.now().timestamp() * 1000),
            adoption_fee=random.randint(5000, 25000),  # cents
            weight_kg=get_realistic_weight(cat_id),
            coat_length=profile["coat_length"],
            coat_color=profile["coat_color"],
            age_months=profile["age_months"],
            favorite_food=profile["favorite_food"],
            sociability_score=profile["sociability_score"],
            favorite_toy=profile["favorite_toy"],
            vocalization_level=profile["vocalization_level"]
        )
        
        producer.send(TOPIC_ADOPTION_EVENTS, key=event.event_id, value=event)
        print(f"[ADOPTION] {event.event_type} for cat {event.cat_id}")
        
        await asyncio.sleep(random.uniform(1, 5))

async def produce_weight_readings(producer):
    """Produce weight readings"""
    while True:
        cat_id = get_random_cat_id()
        
        event = CatWeightReading(
            reading_id=str(uuid.uuid4()),
            cat_id=cat_id,
            weight_kg=get_realistic_weight(cat_id),
            scale_id=f"scale_{random.randint(1, 5):02d}",
            timestamp=int(datetime.now().timestamp() * 1000)
        )
        
        producer.send(TOPIC_WEIGHT_READINGS, key=event.reading_id, value=event)
        print(f"[WEIGHT] Cat {event.cat_id} - {event.weight_kg}kg")
        
        await asyncio.sleep(random.uniform(5, 15))

async def produce_revenue_events(producer):
    """Produce revenue events"""
    while True:
        revenue_type = random.choice(REVENUE_TYPES)
        
        if revenue_type == 'adoption_fee':
            amount = Decimal(str(round(random.uniform(50.00, 250.00), 2)))
            cat_id = get_random_cat_id()
        elif revenue_type == 'cafe_visit':
            amount = Decimal(str(round(random.uniform(15.00, 45.00), 2)))
            cat_id = get_random_cat_id() if random.random() > 0.3 else None
        elif revenue_type == 'merchandise':
            amount = Decimal(str(round(random.uniform(10.00, 75.00), 2)))
            cat_id = get_random_cat_id() if random.random() > 0.5 else None
        else:  # photo_session
            amount = Decimal(str(round(random.uniform(20.00, 60.00), 2)))
            cat_id = get_random_cat_id()
        
        event = CafeRevenue(
            transaction_id=str(uuid.uuid4()),
            cat_id=cat_id,
            revenue_type=revenue_type,
            amount=amount,
            visitor_id=f"visitor_{random.randint(1, 500):03d}",
            timestamp=int(datetime.now().timestamp() * 1000)
        )
        
        producer.send(TOPIC_CAFE_REVENUE, key=event.transaction_id, value=event)
        cat_info = f" for cat {event.cat_id}" if event.cat_id else ""
        print(f"[REVENUE] ${event.amount:.2f} {event.revenue_type}{cat_info}")
        
        await asyncio.sleep(random.uniform(2, 8))

async def run_all_producers(bootstrap_servers):
    """Run all producers concurrently"""
    producer = create_producer(bootstrap_servers)
    print(f"Starting all Cat Cafe data producers connecting to {bootstrap_servers}...")
    
    try:
        # Run all producers concurrently
        await asyncio.gather(
            produce_cat_interactions(producer),
            produce_adoption_events(producer),
            produce_weight_readings(producer),
            produce_revenue_events(producer)
        )
    except KeyboardInterrupt:
        pass
    finally:
        try:
            producer.close(timeout=1)
        except:
            pass
