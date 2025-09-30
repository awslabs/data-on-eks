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

