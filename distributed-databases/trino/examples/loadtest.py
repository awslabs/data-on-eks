import concurrent.futures
import time
import argparse
import trino
from trino.dbapi import connect

def run_query(endpoint, query, num_executions):
    conn = connect(
        host=endpoint.split(':')[0],
        port=int(endpoint.split(':')[1]),
        user='admin',
        catalog='hive',
        schema='taxi_hive_database'
    )
    cur = conn.cursor()

    for _ in range(num_executions):
        cur.execute(query)
        cur.fetchall()

    cur.close()
    conn.close()

def load_test(endpoint, num_queries, total_queries):
    query = "select * from hive a join hive b on a.vendorid = b.vendorid and a.trip_distance > b.trip_distance limit 100"

    start_time = time.time()
    num_executions_per_query = total_queries // num_queries

    with concurrent.futures.ThreadPoolExecutor(max_workers=num_queries) as executor:
        futures = [executor.submit(run_query, endpoint, query, num_executions_per_query) for _ in range(num_queries)]
        for future in concurrent.futures.as_completed(futures):
            future.result()

    end_time = time.time()

    print(f"Load test completed in {end_time - start_time:.2f} seconds.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run load test against Trino engine.")
    parser.add_argument("--endpoint", required=True, help="Trino endpoint (e.g., *************:8080)")
    parser.add_argument("--num-queries", type=int, required=True, help="Number of concurrent queries")
    parser.add_argument("--total-queries", type=int, required=True, help="Total number of queries to execute")
    args = parser.parse_args()

    load_test(args.endpoint, args.num_queries, args.total_queries)
