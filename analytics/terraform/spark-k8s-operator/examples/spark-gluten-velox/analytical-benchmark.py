#!/usr/bin/env python3
"""
Analytical Benchmark Script for Spark vs Spark + Gluten + Velox

This script generates realistic analytical workloads to compare performance
between native Spark and Spark with Gluten+Velox backend.

Based on proven patterns that benefit from vectorized execution:
- Complex aggregations with multiple functions
- Star schema joins with dimension tables
- Top-K queries with sorting
- Rollup/cube operations
"""

import sys
import time
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql import types as T

class AnalyticalBenchmark:
    def __init__(self, app_name="analytical-benchmark", enable_gluten=False):
        self.app_name = app_name
        self.enable_gluten = enable_gluten
        self.spark = self._create_spark_session()
        self.results = {}

    def _create_spark_session(self):
        """Create Spark session with or without Gluten"""
        builder = SparkSession.builder.appName(self.app_name)

        # Common configurations for performance
        builder = builder.config("spark.sql.adaptive.enabled", "true") \
                        .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
                        .config("spark.sql.adaptive.skewJoin.enabled", "true") \
                        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer") \
                        .config("spark.sql.adaptive.localShuffleReader.enabled", "true")

        if self.enable_gluten:
            # Gluten + Velox specific configurations
            builder = builder.config("spark.plugins", "org.apache.gluten.GlutenPlugin") \
                            .config("spark.shuffle.manager", "org.apache.spark.shuffle.sort.ColumnarShuffleManager") \
                            .config("spark.memory.offHeap.enabled", "true") \
                            .config("spark.memory.offHeap.size", "2g") \
                            .config("spark.sql.execution.arrow.pyspark.enabled", "true")

        return builder.getOrCreate()

    def generate_synthetic_data(self, n_rows=10_000_000, n_prod=10_000, n_ctry=50, n_ch=8, n_days=365, repart=128):
        """Generate realistic synthetic data with skew patterns"""
        print(f"📊 Generating synthetic data: {n_rows:,} rows")
        print(f"   Products: {n_prod:,}, Countries: {n_ctry}, Channels: {n_ch}, Days: {n_days}")

        # --------- Synthetic, skewed FACT ----------
        # Zipf-ish distribution for realistic skew patterns
        fact = (
            self.spark.range(n_rows)
              .select(
                  # Skewed product distribution (Zipf-like)
                  (F.floor(F.pow(F.rand()*0.999999 + 1e-9, 3) * n_prod)).alias("product_id"),
                  # Slightly skewed countries
                  (F.floor(F.pow(F.rand()*0.999999 + 1e-9, 1.7) * n_ctry)).alias("country_id"),
                  # Slightly skewed channels
                  (F.floor(F.pow(F.rand()*0.999999 + 1e-9, 1.4) * n_ch)).alias("channel_id"),
                  # Random day
                  (F.floor(F.rand() * n_days)).alias("day_idx"),
                  # Economics with realistic ranges
                  (F.round(F.rand()*90 + 10, 2)).alias("price"),
                  (F.floor(F.rand()*5 + 1)).alias("qty"),
                  (F.round(F.rand()*0.25, 4)).alias("discount")
              )
              .withColumn("revenue", F.col("price") * F.col("qty") * (1 - F.col("discount")))
              .repartition(repart)
              .cache()
        )

        # --------- Dimension Tables ----------
        countries = (
            self.spark.range(n_ctry)
                .select(
                    F.col("id").alias("country_id"),
                    F.concat(F.lit("Country_"), F.lpad(F.col("id").cast("string"), 3, "0")).alias("country_name"),
                    F.when(F.col("id") % 4 == 0, "Americas")
                     .when(F.col("id") % 4 == 1, "Europe")
                     .when(F.col("id") % 4 == 2, "Asia")
                     .otherwise("Rest of World").alias("region"),
                    (F.rand()*0.25 + 0.75).alias("vat_rate")
                )
                .cache()
        )

        channels = (
            self.spark.range(n_ch)
                .select(
                    F.col("id").alias("channel_id"),
                    F.array(F.lit("web"), F.lit("store"), F.lit("partner"), F.lit("marketplace"),
                            F.lit("mobile_app"), F.lit("phone"), F.lit("catalog"), F.lit("social"))
                     .getItem(F.col("id") % 8).alias("channel_name"),
                    F.when(F.col("id") % 2 == 0, "digital").otherwise("physical").alias("channel_type")
                )
                .cache()
        )

        calendar = (
            self.spark.range(n_days)
                 .select(
                     F.col("id").cast("int").alias("day_idx"),
                     F.date_add(F.date_sub(F.current_date(), n_days), F.col("id").cast("int")).alias("date_key")
                 )
                 .withColumn("year", F.year("date_key"))
                 .withColumn("month", F.month("date_key"))
                 .withColumn("quarter", F.quarter("date_key"))
                 .withColumn("day_of_week", F.dayofweek("date_key"))
                 .cache()
        )

        # Materialize dimensions
        print(f"   Fact table: {fact.count():,} rows")
        print(f"   Countries: {countries.count():,} rows")
        print(f"   Channels: {channels.count():,} rows")
        print(f"   Calendar: {calendar.count():,} rows")

        return fact, countries, channels, calendar

    def time_query(self, label, df, write_mode="count"):
        """Time a query execution"""
        print(f"\n🚀 Running: {label}")
        print(f"   Backend: {'Gluten+Velox' if self.enable_gluten else 'Native Spark'}")

        start = time.time()

        if write_mode == "count":
            rows = df.count()
        else:
            # For more realistic timing, actually materialize the results
            df.write.mode("overwrite").format("noop").save()
            rows = df.count()

        elapsed = time.time() - start

        print(f"   ✅ Completed: {rows:,} rows in {elapsed:.2f}s")

        self.results[label] = {
            'backend': 'Gluten+Velox' if self.enable_gluten else 'Native Spark',
            'execution_time': elapsed,
            'rows': rows
        }

        return elapsed

    def query_a_complex_aggregations(self, fact):
        """Complex multi-function aggregations - Gluten excels here"""
        print("\n" + "="*60)
        print("QUERY A: Complex Multi-Function Aggregations")
        print("="*60)

        # Many aggregates that Gluten accelerates well
        df = (
            fact
              .withColumn("is_discounted", (F.col("discount") > 0.05).cast("int"))
              .withColumn("high_value", (F.col("revenue") > 100).cast("int"))
              .groupBy("country_id", "channel_id")
              .agg(
                  F.count("*").alias("total_orders"),
                  F.sum("qty").alias("total_quantity"),
                  F.sum("revenue").alias("total_revenue"),
                  F.avg("price").alias("avg_price"),
                  F.min("price").alias("min_price"),
                  F.max("price").alias("max_price"),
                  F.stddev_pop("price").alias("stddev_price"),
                  F.approx_count_distinct("product_id").alias("unique_products"),
                  F.sum("is_discounted").alias("discounted_orders"),
                  F.sum("high_value").alias("high_value_orders"),
                  F.avg("discount").alias("avg_discount"),
                  F.expr("percentile_approx(revenue, 0.5)").alias("median_revenue"),
                  F.expr("percentile_approx(revenue, array(0.25,0.75))").alias("revenue_quartiles")
              )
              .filter(F.col("total_revenue") > 1000)
              .orderBy(F.desc("total_revenue"))
        )

        return self.time_query("Query_A_Complex_Aggregations", df)

    def query_b_star_schema_join(self, fact, countries, channels, calendar):
        """Star schema joins with aggregations - Benefits from columnar processing"""
        print("\n" + "="*60)
        print("QUERY B: Star Schema Join with Aggregations")
        print("="*60)

        df = (
            fact.join(F.broadcast(countries), "country_id", "inner")
                .join(F.broadcast(channels), "channel_id", "inner")
                .join(F.broadcast(calendar), "day_idx", "inner")
                .withColumn("gross_revenue", F.col("revenue"))
                .withColumn("net_revenue", F.col("revenue") / F.col("vat_rate"))
                .withColumn("margin", F.col("revenue") - (F.col("price") * F.col("qty") * 0.6))
                .groupBy("region", "channel_type", "year", "quarter")
                .agg(
                    F.sum("gross_revenue").alias("gross_revenue"),
                    F.sum("net_revenue").alias("net_revenue"),
                    F.sum("margin").alias("total_margin"),
                    F.countDistinct("product_id").alias("unique_skus"),
                    F.countDistinct("country_id").alias("countries_served"),
                    F.avg("price").alias("avg_price"),
                    F.sum("qty").alias("total_units")
                )
                .withColumn("margin_pct", F.col("total_margin") / F.col("gross_revenue") * 100)
                .filter(F.col("gross_revenue") > 10000)
                .orderBy(F.desc("gross_revenue"))
        )

        return self.time_query("Query_B_Star_Schema_Join", df)

    def query_c_rollup_analysis(self, fact, calendar):
        """Rollup operations with multiple grouping levels"""
        print("\n" + "="*60)
        print("QUERY C: Rollup Analysis (Cube-like)")
        print("="*60)

        df = (
            fact.join(F.broadcast(calendar), "day_idx", "inner")
                .rollup("year", "quarter", "country_id", "channel_id")
                .agg(
                    F.sum("revenue").alias("total_revenue"),
                    F.sum("qty").alias("total_qty"),
                    F.count("*").alias("order_count"),
                    F.avg("discount").alias("avg_discount"),
                    F.countDistinct("product_id").alias("product_variety")
                )
                .filter(F.col("total_revenue").isNotNull())
                .filter(F.col("total_revenue") > 500)
                .withColumn("revenue_per_order", F.col("total_revenue") / F.col("order_count"))
                .orderBy(F.desc("total_revenue"))
        )

        return self.time_query("Query_C_Rollup_Analysis", df)

    def query_d_top_k_analysis(self, fact, countries, channels):
        """Top-K analysis with window functions and sorting"""
        print("\n" + "="*60)
        print("QUERY D: Top-K Analysis with Window Functions")
        print("="*60)

        # First get product performance by country and channel
        product_performance = (
            fact.join(F.broadcast(countries), "country_id", "inner")
                .join(F.broadcast(channels), "channel_id", "inner")
                .groupBy("product_id", "country_name", "channel_name")
                .agg(
                    F.sum("revenue").alias("product_revenue"),
                    F.sum("qty").alias("product_qty"),
                    F.count("*").alias("order_count")
                )
        )

        # Then apply window functions for ranking
        from pyspark.sql.window import Window

        country_window = Window.partitionBy("country_name").orderBy(F.desc("product_revenue"))
        channel_window = Window.partitionBy("channel_name").orderBy(F.desc("product_revenue"))

        df = (
            product_performance
                .withColumn("country_rank", F.row_number().over(country_window))
                .withColumn("channel_rank", F.row_number().over(channel_window))
                .withColumn("country_revenue_pct",
                           F.col("product_revenue") / F.sum("product_revenue").over(Window.partitionBy("country_name")) * 100)
                .filter((F.col("country_rank") <= 100) | (F.col("channel_rank") <= 50))
                .orderBy(F.desc("product_revenue"))
                .limit(10000)
        )

        return self.time_query("Query_D_Top_K_Analysis", df)

    def query_e_string_processing(self, fact, countries, channels):
        """String processing and transformations"""
        print("\n" + "="*60)
        print("QUERY E: String Processing & Transformations")
        print("="*60)

        df = (
            fact.join(F.broadcast(countries), "country_id", "inner")
                .join(F.broadcast(channels), "channel_id", "inner")
                .withColumn("product_code", F.concat(F.lit("SKU-"), F.lpad(F.col("product_id").cast("string"), 8, "0")))
                .withColumn("country_upper", F.upper(F.col("country_name")))
                .withColumn("channel_category",
                           F.when(F.col("channel_name").isin("web", "mobile_app", "social"), "Digital")
                            .when(F.col("channel_name").isin("store", "catalog"), "Traditional")
                            .otherwise("Partner"))
                .withColumn("price_tier",
                           F.when(F.col("price") < 25, "Budget")
                            .when(F.col("price") < 75, "Mid-Range")
                            .otherwise("Premium"))
                .withColumn("revenue_description",
                           F.concat(F.lit("Revenue: $"), F.format_number(F.col("revenue"), 2)))
                .groupBy("channel_category", "price_tier", "country_upper")
                .agg(
                    F.count("*").alias("transaction_count"),
                    F.sum("revenue").alias("total_revenue"),
                    F.collect_set("product_code").alias("product_codes"),
                    F.approx_count_distinct("product_id").alias("unique_products")
                )
                .withColumn("avg_transaction_value", F.col("total_revenue") / F.col("transaction_count"))
                .filter(F.col("transaction_count") > 100)
                .orderBy(F.desc("total_revenue"))
        )

        return self.time_query("Query_E_String_Processing", df)

    def run_all_benchmarks(self, scale_factor=1.0):
        """Run complete benchmark suite"""
        print(f"\n🎯 Starting Analytical Benchmark Suite")
        print(f"Backend: {'Gluten+Velox' if self.enable_gluten else 'Native Spark'}")
        print(f"Scale Factor: {scale_factor}x")
        print(f"Timestamp: {time.strftime('%Y-%m-%d %H:%M:%S')}")

        # Scale data size based on factor
        base_rows = int(5_000_000 * scale_factor)
        base_products = int(5_000 * scale_factor)

        # Generate data
        fact, countries, channels, calendar = self.generate_synthetic_data(
            n_rows=base_rows,
            n_prod=base_products,
            n_ctry=25,
            n_ch=8,
            n_days=365,
            repart=max(64, int(128 * scale_factor))
        )

        # Run benchmarks
        benchmarks = [
            lambda: self.query_a_complex_aggregations(fact),
            lambda: self.query_b_star_schema_join(fact, countries, channels, calendar),
            lambda: self.query_c_rollup_analysis(fact, calendar),
            lambda: self.query_d_top_k_analysis(fact, countries, channels),
            lambda: self.query_e_string_processing(fact, countries, channels)
        ]

        for benchmark in benchmarks:
            try:
                benchmark()
                time.sleep(2)  # Brief pause between queries
            except Exception as e:
                print(f"❌ Benchmark failed: {e}")

        # Cleanup
        fact.unpersist()
        countries.unpersist()
        channels.unpersist()
        calendar.unpersist()

        return self.results

    def print_summary(self):
        """Print benchmark results summary"""
        if not self.results:
            print("No results to display")
            return

        print(f"\n{'='*80}")
        print(f"BENCHMARK RESULTS - {'Gluten+Velox' if self.enable_gluten else 'Native Spark'}")
        print(f"{'='*80}")

        total_time = 0
        for query, result in self.results.items():
            time_val = result['execution_time']
            rows = result['rows']
            total_time += time_val
            print(f"{query:<35} | {time_val:>8.2f}s | {rows:>12,} rows")

        print(f"{'-'*80}")
        print(f"{'TOTAL EXECUTION TIME':<35} | {total_time:>8.2f}s")
        print(f"{'AVERAGE PER QUERY':<35} | {total_time/len(self.results):>8.2f}s")

def main():
    """Main execution function"""
    if len(sys.argv) < 2:
        print("Usage: python analytical-benchmark.py <mode> [scale_factor]")
        print("Mode: 'native' or 'gluten'")
        print("Scale factor: multiplier for data size (default: 1.0)")
        sys.exit(1)

    mode = sys.argv[1].lower()
    scale_factor = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0

    if mode not in ['native', 'gluten']:
        print("Mode must be 'native' or 'gluten'")
        sys.exit(1)

    enable_gluten = mode == 'gluten'

    # Run benchmark
    benchmark = AnalyticalBenchmark(
        app_name=f"analytical-benchmark-{mode}",
        enable_gluten=enable_gluten
    )

    try:
        results = benchmark.run_all_benchmarks(scale_factor)
        benchmark.print_summary()

    except Exception as e:
        print(f"Benchmark failed: {e}")
        raise
    finally:
        benchmark.spark.stop()

if __name__ == "__main__":
    main()
