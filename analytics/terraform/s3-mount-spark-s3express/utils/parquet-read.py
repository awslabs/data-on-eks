import pandas as pd

# fake -n 1000  -f parquet -c "order_id,customer_id,order_date,item_id,quantity,price" -o input/order.parquet "pyint,pyint,date_this_year,pyint,pyint,pyint"
# read
df = pd.read_parquet('input/order.parquet')
#df = pd.read_parquet('../../utils/output/part-00000-15a83f1a-91fe-4518-a49b-1fac63ecbf49-c000.snappy.parquet')
# print first 20 rows
print(df.head(20))