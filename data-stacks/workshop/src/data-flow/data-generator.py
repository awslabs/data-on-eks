import csv
import random
import uuid
import os
from datetime import datetime, timedelta
from faker import Faker
import psycopg

fake = Faker()

# Sample data for generation
COAT_COLORS = ['tabby', 'calico', 'black', 'orange', 'gray', 'white']
COAT_LENGTHS = ['short', 'medium', 'long']
ARCH_TYPES = ['social_kitten', 'sleepy_senior', 'shy', 'standard']
NUM_ADOPTED_CATS = 10000
NUM_AVAILABLE_CATS = 1000

"""
read from data/cat_names.txt for cat names. Use all of them by randomly picking one.
generate: cat database entity for NUM_ADOPTED_CATS cats with status = adopted where:
    1. coat_color is random from COAT_COLORS defined above.
    1. if 'social_kitten' is selected as arch_type, the age must be between 0-12 months.
    1. age is between 0 - 240 months.
    1. archtypes is one of ARCH_TYPES defined above.
    1. if coat color is black, reduce the chance of this field set by 20%. (multiplier, not addition)
    1. If the age is more than 120 months, reduce the chance of this field by 9%. For every 12 months, above the 120 months, reduce the chance by 9%. (multiplied)
    1. if 'social_kitten' is selected, the adoption rate is increased by 70%. (multiplied)
    1. if the adoption success roll fails according to the chance generated above, start from the start.
    1. admitted date should be sometime in 2025.
    1. adopted date should always be after admitted date
    1. last_checkup_time is now.
    1. use uuid for cat_id


once cats with status=adopted are generated,
generate NUM_AVAILABLE_CATS cats generate status=available with random chances
    1. coat_color is random from COAT_COLORS defined above.
    4. admitted date should be sometime in 2025.
    5. adopted date should always be after admitted date
    6. last_checkup_time is now.
    5. use uuid for cat_id
"""


def load_cat_names():
    with open('data/cat_names.txt', 'r') as f:
        return [name.strip() for name in f.readlines()]

def calculate_adoption_rate(archetype, coat_color, age):
    rate = 0.5  # Base 50%

    if archetype == 'social_kitten':
        rate *= 1.7  # Increase by 70%

    if coat_color == 'black':
        rate *= 0.8  # Reduce by 20%

    if age > 120:
        months_over = age - 120
        reduction_periods = months_over // 12
        rate *= (0.91 ** reduction_periods)  # 9% reduction per 12 months

    return min(rate, 1.0)

def generate_cats():
    cat_names = load_cat_names()
    cats = []

    # Generate adopted cats
    while len([c for c in cats if c['status'] == 'adopted']) < NUM_ADOPTED_CATS:
        cat_id = str(uuid.uuid4())
        name = random.choice(cat_names)
        coat_color = random.choice(COAT_COLORS)
        coat_length = random.choice(COAT_LENGTHS)
        archetype = random.choice(ARCH_TYPES)

        # Age constraints
        if archetype == 'social_kitten':
            age = random.randint(0, 12)
        else:
            age = random.randint(0, 240)

        # Calculate adoption probability
        adoption_rate = calculate_adoption_rate(archetype, coat_color, age)

        # If adoption roll fails, start over
        if random.random() >= adoption_rate:
            continue

        # Dates
        admitted_date = fake.date_between(start_date=datetime(2025, 1, 1), end_date=datetime(2025, 12, 31))
        adopted_date = fake.date_between(start_date=admitted_date, end_date=datetime(2025, 12, 31))
        last_checkup_time = datetime.now()

        cats.append({
            'cat_id': cat_id,
            'name': name,
            'coat_color': coat_color,
            'coat_length': coat_length,
            'age': age,
            'archetype': archetype,
            'status': 'adopted',
            'admitted_date': admitted_date.strftime('%Y-%m-%d'),
            'adopted_date': adopted_date.strftime('%Y-%m-%d'),
            'last_checkup_time': last_checkup_time.strftime('%Y-%m-%d %H:%M:%S')
        })

    # Generate available cats
    for _ in range(NUM_AVAILABLE_CATS):
        cat_id = str(uuid.uuid4())
        name = random.choice(cat_names)
        coat_color = random.choice(COAT_COLORS)
        coat_length = random.choice(COAT_LENGTHS)
        archetype = random.choice(ARCH_TYPES)

        # Age constraints
        if archetype == 'social_kitten':
            age = random.randint(0, 12)
        else:
            age = random.randint(0, 240)

        # Dates
        admitted_date = fake.date_between(start_date=datetime(2025, 1, 1), end_date=datetime(2025, 12, 31))
        last_checkup_time = datetime.now()

        cats.append({
            'cat_id': cat_id,
            'name': name,
            'coat_color': coat_color,
            'coat_length': coat_length,
            'age': age,
            'archetype': archetype,
            'status': 'available',
            'admitted_date': admitted_date.strftime('%Y-%m-%d'),
            'adopted_date': '',
            'last_checkup_time': last_checkup_time.strftime('%Y-%m-%d %H:%M:%S')
        })

    return cats

def write_csv(data, filename, fieldnames):
    with open(filename, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(data)


VISITOR_ARCHETYPES = ['potential_adopter', 'casual_visitor', 'family', 'cat_lover']

def generate_visitors():
    visitors = []

    for _ in range(1000):
        visitor_id = str(uuid.uuid4())
        name = fake.first_name() + " " + fake.last_name()
        archetype = random.choice(VISITOR_ARCHETYPES)
        first_visit_date = fake.date_between(start_date=datetime(2025, 1, 1), end_date=datetime(2025, 12, 31))

        visitors.append({
            'visitor_id': visitor_id,
            'name': name,
            'archetype': archetype,
            'first_visit_date': first_visit_date.strftime('%Y-%m-%d')
        })

    return visitors


DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "workshop")
DB_USER = os.getenv("DB_USER", "workshop")
DB_PASSWORD = os.getenv("DB_PASSWORD", "workshop")
CONN_STRING = f"dbname='{DB_NAME}' user='{DB_USER}' host='{DB_HOST}' port='{DB_PORT}' password='{DB_PASSWORD}'"

def create_cats_table(cursor):
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS cats (
            cat_id VARCHAR(50) PRIMARY KEY,
            name VARCHAR(50) NOT NULL,
            coat_color VARCHAR(50),
            coat_length VARCHAR(50),
            age INT,
            archetype VARCHAR(50) NOT NULL,
            status VARCHAR(20) NOT NULL,
            admitted_date TIMESTAMP NOT NULL,
            adopted_date TIMESTAMP,
            last_checkup_time TIMESTAMP
        )
    """)

def create_visitors_table(cursor):
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS visitors (
            visitor_id VARCHAR(50) PRIMARY KEY,
            name VARCHAR(50) NOT NULL,
            archetype VARCHAR(50) NOT NULL,
            first_visit_date TIMESTAMP NOT NULL
        )
    """)

def create_tables():
    with psycopg.connect(
        CONN_STRING
    ) as conn:
        with conn.cursor() as cursor:
            create_cats_table(cursor)
            create_visitors_table(cursor)



def insert_cats_to_db(cats):
    with psycopg.connect(
        CONN_STRING
    ) as conn:
        with conn.cursor() as cursor:
            # Batch process in chunks of 1000
            batch_size = 1000
            for i in range(0, len(cats), batch_size):
                batch = cats[i:i + batch_size]
                data = []
                for cat in batch:
                    adopted_date = datetime.strptime(cat['adopted_date'], '%Y-%m-%d') if cat['adopted_date'] else None
                    data.append((
                        cat['cat_id'], cat['name'], cat['coat_color'], cat['coat_length'],
                        cat['age'], cat['archetype'], cat['status'],
                        datetime.strptime(cat['admitted_date'], '%Y-%m-%d'),
                        adopted_date,
                        datetime.strptime(cat['last_checkup_time'], '%Y-%m-%d %H:%M:%S')
                    ))

                cursor.executemany("""
                    INSERT INTO cats (cat_id, name, coat_color, coat_length, age, archetype, status, admitted_date, adopted_date, last_checkup_time)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, data)
                print(f"Inserted batch {i//batch_size + 1}/{(len(cats)-1)//batch_size + 1}")

def insert_visitors_to_db(visitors):
    with psycopg.connect(
        CONN_STRING
    ) as conn:
        with conn.cursor() as cursor:
            data = [(v['visitor_id'], v['name'], v['archetype'], datetime.strptime(v['first_visit_date'], '%Y-%m-%d')) for v in visitors]

            cursor.executemany("""
                INSERT INTO visitors (visitor_id, name, archetype, first_visit_date)
                VALUES (%s, %s, %s, %s)
            """, data)

if __name__ == '__main__':
    cats = generate_cats()
    visitors = generate_visitors()

    # CSV generation (commented out)
    # write_csv(cats, 'data/cats.csv', ['cat_id', 'name', 'coat_color', 'coat_length', 'age', 'archetype', 'status', 'admitted_date', 'adopted_date', 'last_checkup_time'])
    # print(f"Generated {len(cats)} cats in data/cats.csv")
    # write_csv(visitors, 'data/visitors.csv', ['visitor_id', 'name', 'archetype', 'first_visit_date'])
    # print(f"Generated {len(visitors)} visitors in data/visitors.csv")

    # Database insertion
    print("creating tables")
    create_tables()
    print("generating cats")
    insert_cats_to_db(cats)
    print(f"Inserted {len(cats)} cats into database")
    print("generating visitors")
    insert_visitors_to_db(visitors)
    print(f"Inserted {len(visitors)} visitors into database")
