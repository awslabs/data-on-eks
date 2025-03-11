import pandas as pd
from faker import Faker
import pyarrow as pa
import pyarrow.parquet as pq

# Create a Faker instance
fake = Faker()

# Generate the test data
data = []
for _ in range(2_000_000):
    order_id = fake.uuid4()
    customer_id = fake.uuid4()
    order_date = fake.date_between(start_date='-2y', end_date='today')
    item_id = fake.uuid4()
    quantity = fake.random_int(min=1, max=10)
    price = fake.pydecimal(left_digits=4, right_digits=2, positive=True)
    data.append([order_id, customer_id, order_date, item_id, quantity, price])

# Convert the data to a pandas DataFrame
columns = ['order_id', 'customer_id', 'order_date', 'item_id', 'quantity', 'price']
df = pd.DataFrame(data, columns=columns)

# Convert the DataFrame to a PyArrow Table
table = pa.Table.from_pandas(df)

# Write the data to a Parquet file
pq.write_table(table, 'order.parquet')
print("Data written to 'order.parquet' successfully!")
