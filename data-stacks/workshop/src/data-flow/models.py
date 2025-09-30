from dataclasses import dataclass, asdict, fields
from decimal import Decimal
from typing import Optional, get_origin, get_args, Union, List
from datetime import datetime


ACTIVITIES = ["pet", "play", "feed", "photo", "like"]
CAFE_ITEMS = [
    "espresso",
    "cappuccino",
    "latte",
    "americano",
    "croissant",
    "muffin",
    "bagel",
    "sandwich",
    "cheesecake",
    "hot_chocolate"
]

CAT_LOCATIONS = [
    "southwest_window",
    "entrance_couch",
    "cat_tree_top",
    "sunny_corner",
    "bookshelf_middle",
    "counter_stool",
    "window_perch",
    "cozy_nook",
    "play_area",
    "feeding_station",
    "scratching_post",
    "cushioned_bench",
    "reading_chair",
    "corner_hideaway",
    "cafe_table_under"
]

COAT_COLORS = ['tabby', 'calico', 'black', 'orange', 'gray', 'white']
COAT_LENGTHS = ['short', 'medium', 'long']
ARCHETYPES = ['social_kitten', 'sleepy_senior', 'shy', 'standard']
VISITOR_ARCHETYPES = ['potential_adopter', 'casual_visitor', 'family', 'cat_lover']

@dataclass
class CatProfile:
    cat_id: str
    name: str 
    coat_color: str # one of COAT_COLORS
    coat_length: str # one of COAT_LENGTHS
    age: int
    archetype: str
    status: str # adopted or available
    admitted_date: datetime
    adopted_date: datetime
    last_checkup_time: datetime

@dataclass
class VisitorCheckIn:
    visitor_id: str
    event_time: str


@dataclass
class CatInteraction:
    event_time: str
    cat_id: str
    visitor_id: str
    interaction_type: str  # one of ACTIVITIES


@dataclass
class CafeOrders:
    event_time: str
    order_id: str
    visitor_id: str
    items: List[str] # one or more of CAFE_ITEMS
    total_amount: Decimal


@dataclass
class CatWellness:
    event_time: str
    cat_id: str
    activity_level: float # 0.1 to 10.0
    heart_rate: int
    hours_since_last_drink: float


@dataclass
class CatLocation:
    event_time: str
    cat_id: str
    location: str # one of CAT_LOCATIONS


def schema_to_flink_ddl(schema_dict):
    """Convert schema dictionary to Flink DDL string format"""
    return ',\n            '.join([f"`{field}` {ftype}" for field, ftype in schema_dict.items()])


SCHEMA_MAP = {
    "visitor_checkins": {
        "class": VisitorCheckIn,
        "flink_schema": {
            "visitor_id": "STRING",
            "event_time": "STRING"
        }
    },
    "cat_profiles": {
        "class": CatProfile,
        "flink_schema": {
            "cat_id": "STRING",
            "name": "STRING",
            "coat_color": "STRING",
            "coat_length": "STRING",
            "age": "INT",
            "archetype": "STRING",
            "status": "STRING",
            "admitted_date": "TIMESTAMP",
            "adopted_date": "TIMESTAMP",
            "last_checkup_time": "TIMESTAMP"
        }
    },
    "cat_interactions": {
        "class": CatInteraction,
        "flink_schema": {
            "event_time": "STRING",
            "cat_id": "STRING",
            "visitor_id": "STRING",
            "interaction_type": "STRING"
        }
    },
    "cafe_orders": {
        "class": CafeOrders,
        "flink_schema": {
            "event_time": "STRING",
            "order_id": "STRING",
            "visitor_id": "STRING",
            "items": "ARRAY<STRING>",
            "total_amount": "DECIMAL(10,2)"
        }
    },
    "cat_wellness": {
        "class": CatWellness,
        "flink_schema": {
            "event_time": "STRING",
            "cat_id": "STRING",
            "activity_level": "DOUBLE",
            "heart_rate": "INT",
            "hours_since_last_drink": "DOUBLE"
        }
    },
    "cat_locations": {
        "class": CatLocation,
        "flink_schema": {
            "event_time": "STRING",
            "cat_id": "STRING",
            "location": "STRING"
        }
    }
}
