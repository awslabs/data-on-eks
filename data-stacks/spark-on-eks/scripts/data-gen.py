import pandas as pd
from datetime import datetime, timedelta

import pyarrow as pa

schema_dict = {
    'order_id': pa.int64(),
    'customer_id': pa.int64(),
    'order_date': pa.string(),
    'item_id': pa.int64(),
    'quantity': pa.int64(),
    'price': pa.float64()
}

schema = pa.schema(schema_dict)

orders = []
for i in range(1000):
    order_id = i + 1
    customer_id = (order_id - 1) % 100 + 1
    order_date = (datetime.now() - timedelta(days=i)).strftime('%Y-%m-%d')
    item_id = (order_id - 1) % 10 + 1
    quantity = (order_id - 1) % 5 + 1
    price = (order_id - 1) % 100 + 10.0

    order = {
        'order_id': order_id,
        'customer_id': customer_id,
        'order_date': order_date,
        'item_id': item_id,
        'quantity': quantity,
        'price': price
    }
    orders.append(order)

df = pd.DataFrame(orders)

df.to_parquet('sample_orders.parquet', schema=schema, index=False)
