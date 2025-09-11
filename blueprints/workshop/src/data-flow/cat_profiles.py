import csv
import random
from decimal import Decimal
from typing import Dict, Any

# Global cat profiles cache
_CAT_PROFILES: Dict[str, Dict[str, Any]] = {}
_CAT_IDS = []

def load_cat_profiles(filename='data/cats.csv'):
    """Load cat profiles from CSV file"""
    global _CAT_PROFILES, _CAT_IDS
    
    if _CAT_PROFILES:  # Already loaded
        return
    
    try:
        with open(filename, 'r') as csvfile:
            reader = csv.DictReader(csvfile)
            for row in reader:
                cat_id = row['cat_id']
                _CAT_PROFILES[cat_id] = {
                    'coat_color': row['coat_color'],
                    'coat_length': row['coat_length'],
                    'age_months': int(row['age_months']),
                    'base_weight': Decimal(row['base_weight_kg']),
                    'favorite_food': row['favorite_food'],
                    'favorite_toy': row['favorite_toy'],
                    'sociability_score': int(row['sociability_score']),
                    'vocalization_level': int(row['vocalization_level']),
                    'stress_tendency': row['stress_tendency']
                }
                _CAT_IDS.append(cat_id)
        
        print(f"Loaded {len(_CAT_PROFILES)} cat profiles from {filename}")
    
    except FileNotFoundError:
        print(f"Warning: {filename} not found. Run generate_cats.py first.")
        _CAT_IDS = [f"{i:03d}" for i in range(1, 101)]  # Fallback to 100 cats

def get_cat_profile(cat_id: str) -> Dict[str, Any]:
    """Get profile for a specific cat"""
    load_cat_profiles()
    return _CAT_PROFILES.get(cat_id, {})

def get_realistic_weight(cat_id: str) -> Decimal:
    """Get realistic weight with small variations from base"""
    profile = get_cat_profile(cat_id)
    if not profile:
        return Decimal("4.0")  # Default weight
    
    base_weight = profile["base_weight"]
    # ±15% variation from base weight
    variation = random.uniform(-0.15, 0.15)
    new_weight = base_weight * (1 + Decimal(str(variation)))
    return Decimal(str(round(new_weight, 2)))

def get_realistic_stress_level(cat_id: str) -> int:
    """Get stress level based on cat's tendency"""
    profile = get_cat_profile(cat_id)
    if not profile:
        return random.randint(1, 10)  # Default random
    
    tendency = profile["stress_tendency"]
    
    if tendency == "low":
        return random.randint(1, 4)
    elif tendency == "medium":
        return random.randint(3, 7)
    else:  # high
        return random.randint(6, 10)

def get_random_cat_id() -> str:
    """Get a random cat ID from loaded profiles"""
    load_cat_profiles()
    return random.choice(_CAT_IDS)
