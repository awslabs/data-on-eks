import asyncio
import csv
import json
import random
import time
import uuid
from datetime import datetime
from decimal import Decimal
from dataclasses import asdict
from kafka import KafkaProducer
import os

from models import CatProfile, CatInteraction, AdoptionEvent, CatWeightReading, CafeRevenue

# Configuration
KAFKA_BOOTSTRAP_SERVERS = ['localhost:9094']

# Sample data
INTERACTION_TYPES = ['pet', 'play', 'feed', 'photo']
EVENT_TYPES = ['inquiry', 'application', 'adoption', 'return']
REVENUE_TYPES = ['adoption_fee', 'cafe_visit', 'merchandise', 'photo_session']

# Load cat data from CSV
def load_cat_data():
    cats = {}
    csv_path = os.path.join(os.path.dirname(__file__), 'data', 'cats.csv')
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            cat_profile = CatProfile(
                cat_id=int(row['cat_id']),
                name=row['name'],
                coat_color=row['coat_color'],
                coat_length=row['coat_length'],
                age_months=int(row['age_months']),
                base_weight_kg=Decimal(row['base_weight_kg']),
                favorite_food=row['favorite_food'],
                favorite_toy=row['favorite_toy'],
                sociability_score=int(row['sociability_score']),
                vocalization_level=int(row['vocalization_level']),
                stress_tendency=row['stress_tendency']
            )
            cats[int(row['cat_id'])] = cat_profile
    return cats

CAT_DATA = load_cat_data()
CAT_IDS = list(CAT_DATA.keys())

def create_producer():
    """Create a Kafka producer"""
    def decimal_serializer(obj):
        if isinstance(obj, Decimal):
            return float(obj)
        raise TypeError(f"Object of type {type(obj)} is not JSON serializable")
    
    return KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        value_serializer=lambda v: json.dumps(v, default=decimal_serializer).encode('utf-8'),
        key_serializer=lambda k: k.encode('utf-8') if k else None,
        request_timeout_ms=10000,
        metadata_max_age_ms=10000
    )

async def produce_cat_interactions(producer):
    """Produce cat interaction events"""
    while True:
        cat_id = random.choice(CAT_IDS)
        cat = CAT_DATA[cat_id]
        
        # Stress level based on cat's stress tendency
        if cat.stress_tendency == 'high':
            stress_level = random.randint(6, 10)
        elif cat.stress_tendency == 'medium':
            stress_level = random.randint(3, 7)
        else:  # low
            stress_level = random.randint(1, 4)
        
        interaction = CatInteraction(
            interaction_id=str(uuid.uuid4()),
            cat_id=cat_id,
            visitor_id=f"visitor_{random.randint(1, 3000):03d}",
            interaction_type=random.choice(INTERACTION_TYPES),
            duration_minutes=random.randint(1, 30),
            cat_stress_level=stress_level,
            timestamp=int(datetime.now().timestamp() * 1000)
        )
        producer.send('cat-interactions', key=interaction.interaction_id, value=asdict(interaction))
        print(f"[INTERACTIONS] {interaction.interaction_type} for {cat.name} ({cat_id}) (stress: {interaction.cat_stress_level})")
        
        await asyncio.sleep(random.uniform(0.5, 3))

async def produce_adoption_events(producer):
    """Produce adoption events"""
    while True:
        cat_id = random.choice(CAT_IDS)
        cat = CAT_DATA[cat_id]
        
        adoption_event = AdoptionEvent(
            event_id=str(uuid.uuid4()),
            cat_id=cat_id,
            event_type=random.choice(EVENT_TYPES),
            visitor_id=f"visitor_{random.randint(1, 3000):03d}",
            timestamp=int(datetime.now().timestamp() * 1000),
            adoption_fee=random.randint(5000, 25000),
            weight_kg=cat.base_weight_kg,
            coat_length=cat.coat_length,
            coat_color=cat.coat_color,
            age_months=cat.age_months,
            favorite_food=cat.favorite_food,
            sociability_score=cat.sociability_score,
            favorite_toy=cat.favorite_toy,
            vocalization_level=cat.vocalization_level
        )
        
        producer.send('adoption-events', key=adoption_event.event_id, value=asdict(adoption_event))
        print(f"[ADOPTION] {adoption_event.event_type} for {cat.name} ({cat_id})")
        
        await asyncio.sleep(random.uniform(1, 5))

async def produce_weight_readings(producer):
    """Produce weight readings"""
    while True:
        cat_id = random.choice(CAT_IDS)
        cat = CAT_DATA[cat_id]
        
        # Add variation to base weight (±10%)
        variation = Decimal(str(random.uniform(-0.1, 0.1)))
        weight = (cat.base_weight_kg * (Decimal('1') + variation)).quantize(Decimal('0.01'))
        
        weight_reading = CatWeightReading(
            reading_id=str(uuid.uuid4()),
            cat_id=cat_id,
            weight_kg=weight,
            scale_id=f"scale_{random.randint(1, 5):02d}",
            timestamp=int(datetime.now().timestamp() * 1000)
        )
        
        producer.send('cat-weight-readings', key=weight_reading.reading_id, value=asdict(weight_reading))
        print(f"[WEIGHT] {cat.name} ({cat_id}) - {weight_reading.weight_kg}kg (base: {cat.base_weight_kg}kg)")
        
        await asyncio.sleep(random.uniform(5, 15))

async def produce_revenue_events(producer):
    """Produce revenue events"""
    while True:
        revenue_type = random.choice(REVENUE_TYPES)
        
        if revenue_type == 'adoption_fee':
            amount = Decimal(str(round(random.uniform(50.00, 250.00), 2)))
            cat_id = random.choice(CAT_IDS)
        elif revenue_type == 'cafe_visit':
            amount = Decimal(str(round(random.uniform(15.00, 45.00), 2)))
            cat_id = random.choice(CAT_IDS) if random.random() > 0.3 else None
        elif revenue_type == 'merchandise':
            amount = Decimal(str(round(random.uniform(10.00, 75.00), 2)))
            cat_id = random.choice(CAT_IDS) if random.random() > 0.5 else None
        else:  # photo_session
            amount = Decimal(str(round(random.uniform(20.00, 60.00), 2)))
            cat_id = random.choice(CAT_IDS)
        
        revenue_event = CafeRevenue(
            transaction_id=str(uuid.uuid4()),
            cat_id=cat_id,
            revenue_type=revenue_type,
            amount=amount,
            visitor_id=f"visitor_{random.randint(1, 3000):03d}",
            timestamp=int(datetime.now().timestamp() * 1000)
        )
        
        producer.send('cafe-revenue', key=revenue_event.transaction_id, value=asdict(revenue_event))
        if revenue_event.cat_id:
            cat_name = CAT_DATA[revenue_event.cat_id].name
            cat_info = f" for {cat_name} ({revenue_event.cat_id})"
        else:
            cat_info = ""
        print(f"[REVENUE] ${revenue_event.amount} {revenue_event.revenue_type}{cat_info}")
        
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
