#!/usr/bin/env python3

import os
import json
import time
import random
import signal
import logging
from datetime import datetime
from typing import Dict, List, Optional
# from threading import Thread
# from http.server import HTTPServer, BaseHTTPRequestHandler

import psycopg2
from kafka import KafkaProducer


INTERACTION_TYPES = ['pet', 'play', 'feed', 'photo', 'like']

# Kafka Topics
TOPIC_VISITOR_CHECKINS = 'visitor-checkins'
TOPIC_CAT_INTERACTIONS = 'cat-interactions'
TOPIC_CAFE_ORDERS = 'cafe-orders'
TOPIC_CAT_WELLNESS_IOT = 'cat-wellness-iot'
TOPIC_CAT_LOCATIONS = 'cat-locations'


# Configuration from environment variables
class Config:
    DB_HOST = os.getenv('DB_HOST', 'localhost')
    DB_PORT = int(os.getenv('DB_PORT', 5432))
    DB_USER = os.getenv('DB_USER', 'workshop')
    DB_PASSWORD = os.getenv('DB_PASSWORD', 'workshop')
    DB_NAME = os.getenv('DB_NAME', 'workshop')
    
    KAFKA_BROKERS = os.getenv('KAFKA_BROKERS', 'localhost:9094').split(',')
    SIMULATION_TICK_SECONDS = float(os.getenv('SIMULATION_TICK_SECONDS', 1.0))


# # Health check server
# class HealthHandler(BaseHTTPRequestHandler):
#     def do_GET(self):
#         if self.path == '/healthz':
#             self.send_response(200)
#             self.send_header('Content-type', 'text/plain')
#             self.end_headers()
#             self.wfile.write(b'OK')
#         else:
#             self.send_response(404)
#             self.end_headers()


class CatCafeSimulator:
    def __init__(self):
        self.config = Config()
        self.running = False
        self.db_conn = None
        self.kafka_producer = None
        self.active_visitors = {}  # visitor_id -> session_info
        self.available_cats = []
        self.visitor_personas = []
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s'
        )
        self.logger = logging.getLogger(__name__)
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
    
    def _signal_handler(self, signum, frame):
        self.logger.info(f"Received signal {signum}, shutting down gracefully...")
        self.running = False
        # Force exit if cleanup takes too long
        import threading
        def force_exit():
            time.sleep(5)  # Give 5 seconds for graceful shutdown
            os._exit(1)
        threading.Thread(target=force_exit, daemon=True).start()
    
    def initialize(self):
        """Initialize all connections and set up deterministic mode if needed"""
        self.logger.info("Initializing Cat Cafe Simulator...")
        
        # Initialize database connection
        self._init_database()
        
        # Initialize Kafka producer
        self._init_kafka()
        
        # Seed database if empty
        self._seed_database_if_empty()
        
        # Load initial cache
        self._refresh_cache()
        
        self.logger.info("Initialization complete")
    
    def _init_database(self):
        """Initialize PostgreSQL connection"""
        try:
            self.db_conn = psycopg2.connect(
                host=self.config.DB_HOST,
                port=self.config.DB_PORT,
                database=self.config.DB_NAME,
                user=self.config.DB_USER,
                password=self.config.DB_PASSWORD
            )
            self.logger.info("Database connection established")
        except Exception as e:
            self.logger.error(f"Failed to connect to database: {e}")
            raise
    
    def _init_kafka(self):
        """Initialize Kafka producer"""
        try:
            self.kafka_producer = KafkaProducer(
                bootstrap_servers=self.config.KAFKA_BROKERS,
                retries=3,
                value_serializer=lambda v: json.dumps(v).encode('utf-8')
            )
            self.logger.info("Kafka producer initialized")
        except Exception as e:
            self.logger.error(f"Failed to initialize Kafka producer: {e}")
            raise
    
    def _seed_database_if_empty(self):
        """Check if database is empty and seed if needed"""
        # TODO: Implement database seeding
        self.logger.info("Database seeding check - TODO")
    
    def _refresh_cache(self):
        """Refresh in-memory cache from database"""
        cursor = self.db_conn.cursor()
        
        # Load available cats
        cursor.execute("""
            SELECT cat_id, name, coat_color, coat_length, age, archetype, status
            FROM cats 
            WHERE status = 'available'
        """)
        self.available_cats = [
            {
                'cat_id': row[0], 'name': row[1], 'coat_color': row[2],
                'coat_length': row[3], 'age': row[4], 'archetype': row[5], 'status': row[6]
            }
            for row in cursor.fetchall()
        ]
        
        # Load visitor personas
        cursor.execute("""
            SELECT visitor_id, name, archetype
            FROM visitors
        """)
        self.visitor_personas = [
            {'visitor_id': row[0], 'name': row[1], 'archetype': row[2]}
            for row in cursor.fetchall()
        ]
        
        cursor.close()
        self.logger.info(f"Cache refreshed: {len(self.available_cats)} available cats, {len(self.visitor_personas)} visitor personas")
    
    def run(self):
        """Main simulation loop"""
        self.logger.info("Starting simulation loop...")
        self.running = True
        
        # Start health check server in background
        # health_server = HTTPServer(('0.0.0.0', 8080), HealthHandler)
        # health_thread = Thread(target=health_server.serve_forever, daemon=True)
        # health_thread.start()
        # self.logger.info("Health check server started on port 8080")
        
        last_cache_refresh = time.time()
        last_kafka_flush = time.time()
        
        while self.running:
            tick_start = time.time()
            
            # Refresh cache every 60 seconds
            if time.time() - last_cache_refresh > 60:
                self._refresh_cache()
                last_cache_refresh = time.time()
            
            # Flush Kafka every 5 seconds
            if time.time() - last_kafka_flush > 5:
                try:
                    self.kafka_producer.flush(timeout=1)
                except:
                    pass  # Don't block on flush errors
                last_kafka_flush = time.time()
            
            # Run simulation tick
            self._simulation_tick()
            
            # Sleep for remaining tick time but check running flag frequently
            elapsed = time.time() - tick_start
            sleep_time = max(0, self.config.SIMULATION_TICK_SECONDS - elapsed)
            
            # Sleep in small chunks to be responsive to signals
            while sleep_time > 0 and self.running:
                chunk = min(0.1, sleep_time)
                time.sleep(chunk)
                sleep_time -= chunk
        
        self.logger.info("Simulation loop ended")
        self._cleanup()
    
    def _simulation_tick(self):
        """Execute one simulation tick"""
        # Handle new visitor arrivals (10% chance per tick)
        if random.random() < 0.1 and self.visitor_personas:
            self._new_visitor_arrival()
        
        # Process active visitors
        expired_visitors = []
        for visitor_id, session in list(self.active_visitors.items()):
            session['ticks_remaining'] -= 1
            
            if session['ticks_remaining'] <= 0:
                expired_visitors.append(visitor_id)
            else:
                self._process_visitor_tick(visitor_id, session)
        
        # Remove expired visitors
        for visitor_id in expired_visitors:
            visitor_name = self.active_visitors[visitor_id]['name']
            del self.active_visitors[visitor_id]
            self.logger.info(f"Visitor {visitor_name} session ended")
        
        # Generate cat wellness and location events
        self._process_cat_events()
    
    def _new_visitor_arrival(self):
        """Handle a new visitor arriving at the cafe"""
        visitor_persona = random.choice(self.visitor_personas)
        
        # Determine session duration based on archetype
        archetype = visitor_persona['archetype']
        if archetype == 'potential_adopter':
            session_duration = random.randint(20, 40)  # 20-40 ticks
        elif archetype == 'casual_visitor':
            session_duration = random.randint(10, 20)  # 10-20 ticks
        elif archetype == 'family':
            session_duration = random.randint(30, 60)  # 30-60 ticks
        elif archetype == 'cat_lover':
            session_duration = random.randint(40, 80)  # 40-80 ticks (long session)
        else:
            session_duration = random.randint(15, 30)  # default
        
        # Create session
        session = {
            'visitor_id': visitor_persona['visitor_id'],
            'name': visitor_persona['name'],
            'archetype': archetype,
            'ticks_remaining': session_duration,
            'likes_generated': 0,  # Track likes for potential_adopter
            'orders_made': 0       # Track orders made
        }
        
        self.active_visitors[visitor_persona['visitor_id']] = session
        
        # Generate visitor_checkins event
        self._publish_event(TOPIC_VISITOR_CHECKINS, {
            'event_time': datetime.now().isoformat(timespec='milliseconds') + 'Z',
            'visitor_id': visitor_persona['visitor_id']
        })
        
        self.logger.info(f"Visitor {visitor_persona['name']} ({archetype}) arrived for {session_duration} ticks")
    
    def _process_visitor_tick(self, visitor_id, session):
        """Process one tick for an active visitor"""
        archetype = session['archetype']
        
        if archetype == 'potential_adopter':
            self._process_potential_adopter(visitor_id, session)
        elif archetype == 'casual_visitor':
            self._process_casual_visitor(visitor_id, session)
        elif archetype == 'family':
            self._process_family(visitor_id, session)
        elif archetype == 'cat_lover':
            self._process_cat_lover(visitor_id, session)
    
    def _process_potential_adopter(self, visitor_id, session):
        """Process potential_adopter archetype behavior"""
        # Generate cafe order on arrival (first tick)
        if session['orders_made'] == 0:
            self._generate_cafe_order(visitor_id, 'small')
            session['orders_made'] = 1
        
        # Generate 1-2 cat interactions per tick
        interactions = random.randint(1, 2)
        for _ in range(interactions):
            self._generate_cat_interaction(visitor_id, random.choice(['pet', 'play', 'feed', 'photo']))
        
        # Ensure exactly 4 "like" interactions during session
        if session['likes_generated'] < 4:
            remaining_ticks = session['ticks_remaining']
            if remaining_ticks <= (4 - session['likes_generated']) or random.random() < 0.3:
                self._generate_cat_interaction(visitor_id, 'like')
                session['likes_generated'] += 1
    
    def _process_casual_visitor(self, visitor_id, session):
        """Process casual_visitor archetype behavior"""
        # Generate one cafe order during session
        if session['orders_made'] == 0 and random.random() < 0.2:
            self._generate_cafe_order(visitor_id, 'small')
            session['orders_made'] = 1
        
        # Generate few cat interactions
        if random.random() < 0.4:
            self._generate_cat_interaction(visitor_id, random.choice(['pet', 'play', 'photo']))
        
        # Low probability of like interaction
        if random.random() < 0.08:
            self._generate_cat_interaction(visitor_id, 'like')
    
    def _process_family(self, visitor_id, session):
        """Process family archetype behavior"""
        # Generate large cafe order shortly after arrival
        if session['orders_made'] == 0 and session['ticks_remaining'] < (session.get('initial_duration', 45) - 3):
            self._generate_cafe_order(visitor_id, 'large')
            session['orders_made'] = 1
        
        # High number of petting interactions, prefer social_kittens
        if random.random() < 0.7:
            social_kittens = [cat for cat in self.available_cats if cat['archetype'] == 'social_kitten']
            target_cats = social_kittens if social_kittens else self.available_cats
            if target_cats:
                cat = random.choice(target_cats)
                self._generate_cat_interaction(visitor_id, 'pet', cat['cat_id'])
        
        # Very low probability of like interactions
        if random.random() < 0.03:
            self._generate_cat_interaction(visitor_id, 'like')
    
    def _process_cat_lover(self, visitor_id, session):
        """Process cat_lover archetype behavior"""
        # Generate 1-2 small cafe orders over long session
        if session['orders_made'] < 2 and random.random() < 0.05:
            self._generate_cafe_order(visitor_id, 'small')
            session['orders_made'] += 1
        
        # Moderate petting interactions, prefer shy/sleepy cats
        if random.random() < 0.5:
            preferred_cats = [cat for cat in self.available_cats if cat['archetype'] in ['shy', 'sleepy_senior']]
            target_cats = preferred_cats if preferred_cats else self.available_cats
            if target_cats:
                cat = random.choice(target_cats)
                self._generate_cat_interaction(visitor_id, 'pet', cat['cat_id'])
        
        # Moderate chance of exactly one like during session
        if session['likes_generated'] == 0 and random.random() < 0.15:
            self._generate_cat_interaction(visitor_id, 'like')
            session['likes_generated'] = 1
    
    def _generate_cat_interaction(self, visitor_id, interaction_type, cat_id=None):
        """Generate a cat interaction event"""
        if not cat_id and self.available_cats:
            cat_id = random.choice(self.available_cats)['cat_id']
        
        if cat_id:
            event = {
                'event_time': datetime.now().isoformat(timespec='milliseconds') + 'Z',
                'visitor_id': visitor_id,
                'cat_id': cat_id,
                'interaction_type': interaction_type
            }
            self._publish_event(TOPIC_CAT_INTERACTIONS, event)
    
    def _generate_cafe_order(self, visitor_id, size='small'):
        """Generate a cafe order event"""
        import uuid
        
        cafe_items = [
            "espresso", "cappuccino", "latte", "americano", "croissant",
            "muffin", "bagel", "sandwich", "cheesecake", "hot_chocolate"
        ]
        
        if size == 'large':
            num_items = random.randint(4, 8)
        else:
            num_items = random.randint(1, 3)
        
        items = []
        total_amount = 0.0
        
        for _ in range(num_items):
            item_name = random.choice(cafe_items)
            quantity = random.randint(1, 2) if size == 'large' else 1
            price = random.uniform(3.0, 8.0)
            
            items.append({"name": item_name, "quantity": quantity})
            total_amount += price * quantity
        
        event = {
            'event_time': datetime.now().isoformat(timespec='milliseconds') + 'Z',
            'order_id': str(uuid.uuid4()),
            'visitor_id': visitor_id,
            'items': items,
            'total_amount': round(total_amount, 2)
        }
        
        self._publish_event(TOPIC_CAFE_ORDERS, event)
    
    def _process_cat_events(self):
        """Generate cat wellness and location events for all available cats"""
        for cat in self.available_cats:
            self._generate_cat_wellness(cat)
            
            # Generate location updates occasionally (20% chance per tick)
            if random.random() < 0.2:
                self._generate_cat_location(cat)
    
    def _generate_cat_wellness(self, cat):
        """Generate cat wellness IoT event based on archetype"""
        archetype = cat['archetype']
        cat_id = cat['cat_id']
        
        # Base values
        heart_rate = random.randint(80, 120)
        hours_since_last_drink = random.uniform(0.5, 3.0)
        
        # Archetype-specific behavior
        if archetype == 'sleepy_senior':
            activity_level = random.uniform(1.0, 3.0)  # Consistently low
            
            # 5% chance for dehydration alert
            # if random.random() < 0.05:
            #     hours_since_last_drink = random.uniform(4.0, 6.0)
            #     self.logger.info(f"Triggering dehydration alert for {cat['name']}")
                
        elif archetype == 'social_kitten':
            activity_level = random.uniform(7.0, 10.0)  # Consistently high
            
        elif archetype == 'shy':
            activity_level = random.uniform(2.0, 6.0)  # Normal range
            
            # 3% chance for stress alert (very low activity)
            # if random.random() < 0.03:
            #     activity_level = random.uniform(0.1, 0.9)
            #     self.logger.info(f"Triggering stress alert for {cat['name']}")
                
        else:  # standard
            activity_level = random.uniform(3.0, 7.0)  # Normal range
        
        event = {
            'event_time': datetime.now().isoformat(timespec='milliseconds') + 'Z',
            'cat_id': cat_id,
            'activity_level': round(activity_level, 2),
            'heart_rate': heart_rate,
            'hours_since_last_drink': round(hours_since_last_drink, 2)
        }
        
        self._publish_event(TOPIC_CAT_WELLNESS_IOT, event)
    
    def _generate_cat_location(self, cat):
        """Generate cat location update event"""
        locations = [
            "southwest_window", "entrance_couch", "cat_tree_top", "sunny_corner",
            "bookshelf_middle", "counter_stool", "window_perch", "cozy_nook",
            "play_area", "feeding_station", "scratching_post", "cushioned_bench",
            "reading_chair", "corner_hideaway", "cafe_table_under"
        ]
        
        event = {
            'event_time': datetime.now().isoformat(timespec='milliseconds') + 'Z',
            'cat_id': cat['cat_id'],
            'location': random.choice(locations)
        }
        
        self._publish_event(TOPIC_CAT_LOCATIONS, event)
    
    def _publish_event(self, topic, event_data):
        """Publish event to Kafka topic"""
        try:
            self.kafka_producer.send(topic, event_data)
            # Don't flush on every event - let Kafka batch
        except Exception as e:
            self.logger.error(f"Failed to publish to {topic}: {e}")
    
    def _cleanup(self):
        """Clean up resources"""
        self.logger.info("Starting cleanup...")
        if self.kafka_producer:
            try:
                self.kafka_producer.flush(timeout=2)
                self.kafka_producer.close(timeout=2)
            except Exception as e:
                self.logger.warning(f"Error during Kafka cleanup: {e}")
        if self.db_conn:
            try:
                self.db_conn.close()
            except Exception as e:
                self.logger.warning(f"Error during DB cleanup: {e}")
        self.logger.info("Cleanup complete")


if __name__ == '__main__':
    simulator = CatCafeSimulator()
    simulator.initialize()
    simulator.run()
