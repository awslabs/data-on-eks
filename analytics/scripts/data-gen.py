import numpy as np
import pandas as pd
from datetime import datetime, timedelta
import pyarrow as pa
import pyarrow.parquet as pq

NUM_RECORDS = 7_000_000

# Define the schema
schema = pa.schema({
    'order_id': pa.int64(),
    'customer_id': pa.int64(),
    'order_date': pa.string(),
    'item_id': pa.int64(),
    'quantity': pa.int64(),
    'price': pa.float64()
})

print(f"Generating {NUM_RECORDS:,} records...")

# Generate data using numpy (vectorized, much faster)
order_ids = np.arange(1, NUM_RECORDS + 1)
customer_ids = (order_ids - 1) % 100 + 1
item_ids = (order_ids - 1) % 10 + 1
quantities = (order_ids - 1) % 5 + 1
prices = ((order_ids - 1) % 100 + 10.0).astype(np.float64)

# Generate dates
base_date = datetime.now()
dates = [(base_date - timedelta(days=int(i % 365))).strftime('%Y-%m-%d') for i in range(NUM_RECORDS)]

# Create DataFrame
df = pd.DataFrame({
    'order_id': order_ids,
    'customer_id': customer_ids,
    'order_date': dates,
    'item_id': item_ids,
    'quantity': quantities,
    'price': prices
})

print("Writing to parquet...")
df.to_parquet('order.parquet', schema=schema, index=False)
print(f"Done! Created order.parquet with {NUM_RECORDS:,} records")
