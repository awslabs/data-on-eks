import csv
import random
from faker import Faker

# Sample data for generation
COAT_COLORS = ['tabby', 'calico', 'black', 'orange', 'gray', 'white']
COAT_LENGTHS = ['short', 'medium', 'long']
FAVORITE_FOODS = ['salmon', 'chicken', 'tuna', 'beef', 'turkey']
FAVORITE_TOYS = ['feather', 'ball', 'laser', 'catnip', 'string']
STRESS_TENDENCIES = ['low', 'medium', 'high']

def load_cat_names(filename='data/cat_names.txt'):
    """Load cat names from text file"""
    try:
        with open(filename, 'r') as f:
            return [name.strip() for name in f.readlines() if name.strip()]
    except FileNotFoundError:
        print(f"Warning: {filename} not found, using default names")
        return ['Fluffy', 'Whiskers', 'Mittens', 'Shadow', 'Tiger']

def generate_cats_csv(num_cats=1000, filename='data/cats.csv'):
    """Generate CSV file with cat profiles"""
    cat_names = load_cat_names()

    with open(filename, 'w', newline='') as csvfile:
        fieldnames = [
            'cat_id', 'name', 'coat_color', 'coat_length', 'age_months', 'base_weight_kg',
            'favorite_food', 'favorite_toy', 'sociability_score', 'vocalization_level', 'stress_tendency'
        ]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()

        for i in range(1, num_cats + 1):
            # Use cat_id as seed for consistent generation
            random.seed(hash(i))

            # Age affects weight ranges
            age_months = random.randint(6, 120)  # 6 months to 10 years

            # Weight based on age
            if age_months < 12:  # kitten
                base_weight = round(random.uniform(1.5, 3.5), 2)
            elif age_months < 24:  # young adult
                base_weight = round(random.uniform(3.0, 5.5), 2)
            else:  # adult
                base_weight = round(random.uniform(3.5, 8.0), 2)

            cat = {
                'cat_id': i,
                'name': random.choice(cat_names),
                'coat_color': random.choice(COAT_COLORS),
                'coat_length': random.choice(COAT_LENGTHS),
                'age_months': age_months,
                'base_weight_kg': base_weight,
                'favorite_food': random.choice(FAVORITE_FOODS),
                'favorite_toy': random.choice(FAVORITE_TOYS),
                'sociability_score': random.randint(1, 10),
                'vocalization_level': random.randint(1, 10),
                'stress_tendency': random.choice(STRESS_TENDENCIES)
            }

            writer.writerow(cat)

    # Reset random seed
    random.seed()
    print(f"Generated {num_cats} cats in {filename}")

def generate_visitors_csv(num_visitors=3000, filename='data/visitors.csv'):
    """Generate CSV file with visitor data"""
    fake = Faker()

    with open(filename, 'w', newline='') as csvfile:
        fieldnames = ['id', 'first_name', 'last_name']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()

        for i in range(1, num_visitors + 1):
            visitor = {
                'id': i,
                'first_name': fake.first_name(),
                'last_name': fake.last_name()
            }
            writer.writerow(visitor)

    print(f"Generated {num_visitors} visitors in {filename}")

if __name__ == "__main__":
    generate_cats_csv()
    generate_visitors_csv()
