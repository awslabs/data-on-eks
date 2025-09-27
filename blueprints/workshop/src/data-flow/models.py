from dataclasses import dataclass, asdict, fields
from decimal import Decimal
from typing import Optional, get_origin, get_args, Union


@dataclass
class CatProfile:
    cat_id: int
    name: str
    coat_color: str
    coat_length: str
    age_months: int
    base_weight_kg: Decimal
    favorite_food: str
    favorite_toy: str
    sociability_score: int
    vocalization_level: int
    stress_tendency: str  # high, medium, low


@dataclass
class CatInteraction:
    interaction_id: str
    cat_id: int
    visitor_id: int
    interaction_type: str  # pet, play, feed, photo
    duration_minutes: int
    cat_stress_level: int  # 1-10 scale


@dataclass
class AdoptionEvent:
    event_id: str
    cat_id: int
    event_type: str  # inquiry, application, adoption, return
    visitor_id: int
    adoption_fee: int  # cents initially, evolves to decimal
    weight_kg: Decimal
    coat_length: str  # short, medium, long
    coat_color: str  # tabby, calico, black, orange, gray, white
    age_months: int
    favorite_food: str  # salmon, chicken, tuna, beef, turkey
    sociability_score: int  # 1-10 scale
    favorite_toy: str  # feather, ball, laser, catnip, string
    vocalization_level: int  # 1-10 scale


@dataclass
class CatWeightReading:
    reading_id: str
    cat_id: int
    weight_kg: Decimal
    scale_id: str


@dataclass
class CafeRevenue:
    transaction_id: str
    cat_id: Optional[int]  # null for non-cat specific revenue
    revenue_type: str  # adoption_fee, cafe_visit, merchandise, photo_session
    amount: Decimal
    visitor_id: int


# Intermediate/Enriched Models

@dataclass
class EnrichedInteraction:
    interaction_id: str
    cat_id: int
    visitor_id: int
    interaction_type: str
    duration_minutes: int
    cat_stress_level: int
    # Enriched fields
    weight_kg: Decimal
    coat_color: str
    coat_length: str
    age_months: int
    sociability_score: int


@dataclass
class DailyCatMetrics:
    cat_id: int
    date: str  # date format
    total_interactions: int
    avg_stress_level: Decimal
    total_interaction_time: int
    weight_kg: Decimal
    behavioral_score_change: Decimal


# Alert Models

@dataclass
class WeightAlert:
    alert_id: str
    cat_id: int
    alert_type: str
    message: str
    severity: str  # HIGH, MEDIUM, LOW
    current_weight: Decimal
    previous_weight: Decimal
    weight_change_percent: Decimal


@dataclass
class BehavioralAlert:
    alert_id: str
    cat_id: int
    alert_type: str
    message: str
    severity: str
    current_score: int
    baseline_score: int
    score_change: int


@dataclass
class CatPopularity:
    cat_id: int
    like_count: int
    window_start: int  # timestamp
    window_end: int    # timestamp


@dataclass
class PotentialAdopter:
    alert_id: str
    visitor_id: int
    total_likes: int
    threshold: int


def schema_to_flink_ddl(schema_dict):
    """Convert schema dictionary to Flink DDL string format"""
    return ',\n            '.join([f"`{field}` {ftype}" for field, ftype in schema_dict.items()])


SCHEMA_MAP = {
    "cat_profile": {
        "class": CatProfile,
        "flink_schema": {
            "cat_id": "INT",
            "name": "STRING",
            "coat_color": "STRING",
            "coat_length": "STRING",
            "age_months": "INT",
            "base_weight_kg": "DECIMAL(10,2)",
            "favorite_food": "STRING",
            "favorite_toy": "STRING",
            "sociability_score": "INT",
            "vocalization_level": "INT",
            "stress_tendency": "STRING"
        }
    },
    "cat_interactions": {
        "class": CatInteraction,
        "flink_schema": {
            "interaction_id": "STRING",
            "cat_id": "INT",
            "visitor_id": "INT",
            "interaction_type": "STRING",
            "duration_minutes": "INT",
            "cat_stress_level": "INT"
        }
    },
    "adoption_events": {
        "class": AdoptionEvent,
        "flink_schema": {
            "event_id": "STRING",
            "cat_id": "INT",
            "event_type": "STRING",
            "visitor_id": "INT",
            "adoption_fee": "INT",
            "weight_kg": "DECIMAL(10,2)",
            "coat_length": "STRING",
            "coat_color": "STRING",
            "age_months": "INT",
            "favorite_food": "STRING",
            "sociability_score": "INT",
            "favorite_toy": "STRING",
            "vocalization_level": "INT"
        }
    },
    "weight_readings": {
        "class": CatWeightReading,
        "flink_schema": {
            "reading_id": "STRING",
            "cat_id": "INT",
            "weight_kg": "DECIMAL(10,2)",
            "scale_id": "STRING"
        }
    },
    "cafe_revenues": {
        "class": CafeRevenue,
        "flink_schema": {
            "transaction_id": "STRING",
            "cat_id": "INT",
            "revenue_type": "STRING",
            "amount": "DECIMAL(10,2)",
            "visitor_id": "INT"
        }
    },
    "cat_popularity": {
        "python_dict": CatPopularity,
        "flink_schema": {
            "cat_id": "INT",
            "like_count": "INT",
            "window_start": "BIGINT",
            "window_end": "BIGINT"
        }
    },
    "potential_adopter": {
        "python_dict": PotentialAdopter,
        "flink_schema": {
            "alert_id": "STRING",
            "visitor_id": "INT",
            "total_likes": "INT",
            "threshold": "INT"
        }
    }
}
