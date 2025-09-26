from dataclasses import dataclass, asdict, fields
from decimal import Decimal
from typing import Optional, get_origin, get_args


@dataclass
class CatProfile:
    cat_id: str
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
    cat_id: str
    visitor_id: str
    interaction_type: str  # pet, play, feed, photo
    duration_minutes: int
    cat_stress_level: int  # 1-10 scale
    timestamp: int


@dataclass
class AdoptionEvent:
    event_id: str
    cat_id: str
    event_type: str  # inquiry, application, adoption, return
    visitor_id: str
    timestamp: int
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
    cat_id: str
    weight_kg: Decimal
    scale_id: str
    timestamp: int


@dataclass
class CafeRevenue:
    transaction_id: str
    cat_id: Optional[str]  # null for non-cat specific revenue
    revenue_type: str  # adoption_fee, cafe_visit, merchandise, photo_session
    amount: Decimal
    visitor_id: str
    timestamp: int


# Intermediate/Enriched Models

@dataclass
class EnrichedInteraction:
    interaction_id: str
    cat_id: str
    visitor_id: str
    interaction_type: str
    duration_minutes: int
    cat_stress_level: int
    timestamp: int
    # Enriched fields
    weight_kg: Decimal
    coat_color: str
    coat_length: str
    age_months: int
    sociability_score: int


@dataclass
class DailyCatMetrics:
    cat_id: str
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
    cat_id: str
    alert_type: str
    message: str
    severity: str  # HIGH, MEDIUM, LOW
    timestamp: int
    current_weight: Decimal
    previous_weight: Decimal
    weight_change_percent: Decimal


@dataclass
class BehavioralAlert:
    alert_id: str
    cat_id: str
    alert_type: str
    message: str
    severity: str
    timestamp: int
    current_score: int
    baseline_score: int
    score_change: int


def generate_flink_schema(dataclass_type):
    """Generate Flink DDL schema and field list from dataclass"""
    schema_parts = []
    field_names = []
    
    for field in fields(dataclass_type):
        field_name = f"`{field.name}`" if field.name == 'timestamp' else field.name
        
        # Map Python types to Flink types
        if field.type == str:
            flink_type = 'STRING'
        elif field.type == int:
            if field.name == 'timestamp':
                flink_type = 'BIGINT'
            else:
                flink_type = 'INT'
        elif field.type == Decimal:
            flink_type = 'DECIMAL(4,2)'
        elif get_origin(field.type) is type(None):  # Optional
            flink_type = 'STRING'
        else:
            flink_type = 'STRING'
        
        schema_parts.append(f"{field_name} {flink_type}")
        field_names.append(field_name)
    
    schema_parts.append("date_partition STRING")
    return ',\n            '.join(schema_parts), field_names
