import time
import os
import sys
from pyspark import broadcast, SparkContext
from pyspark.conf import SparkConf
from pyspark.sql import SparkSession, HiveContext
from pyspark.sql.functions import *
from pyspark.sql.types import *
from pyspark.sql.window import Window
# Import ML Libraries
from xgboost.spark import SparkXGBClassifier, SparkXGBClassifierModel
from pyspark.ml.evaluation import MulticlassClassificationEvaluator

dataRoot = None

if len(sys.argv) > 2:
   dataRoot = sys.argv[1]
   outputRoot = sys.argv[2]
   num_workers = sys.argv[3]
else:
   print("Data Root path not provided")
   sys.exit(1)

orig_raw_path = f"{dataRoot}/fannie-mae-single-family-loan-performance/"
orig_raw_path_csv2parquet = f"{outputRoot}/csv2parquet/"

# Create spark session
spark = SparkSession\
            .builder.appName("EMR-XGBoost-Spark-GPU")\
            .enableHiveSupport()\
            .getOrCreate()

# Set True to save processed dataset after ETL
# Set False, the dataset after ETL will be directly used in XGBoost train and transform

is_save_dataset=True
output_path_data=f"{outputRoot}/fannie-mae-single-family-loan-performance/mortgage/output/data/"
# the path to save the xgboost model
output_path_model=f"{outputRoot}/fannie-mae-single-family-loan-performance/mortgage/output/model/"

# File schema
_csv_raw_schema = StructType([
      StructField("reference_pool_id", StringType()),
      StructField("loan_id", LongType()),
      StructField("monthly_reporting_period", StringType()),
      StructField("orig_channel", StringType()),
      StructField("seller_name", StringType()),
      StructField("servicer", StringType()),
      StructField("master_servicer", StringType()),
      StructField("orig_interest_rate", DoubleType()),
      StructField("interest_rate", DoubleType()),
      StructField("orig_upb", DoubleType()),
      StructField("upb_at_issuance", StringType()),
      StructField("current_actual_upb", DoubleType()),
      StructField("orig_loan_term", IntegerType()),
      StructField("orig_date", StringType()),
      StructField("first_pay_date", StringType()),
      StructField("loan_age", DoubleType()),
      StructField("remaining_months_to_legal_maturity", DoubleType()),
      StructField("adj_remaining_months_to_maturity", DoubleType()),
      StructField("maturity_date", StringType()),
      StructField("orig_ltv", DoubleType()),
      StructField("orig_cltv", DoubleType()),
      StructField("num_borrowers", DoubleType()),
      StructField("dti", DoubleType()),
      StructField("borrower_credit_score", DoubleType()),
      StructField("coborrow_credit_score", DoubleType()),
      StructField("first_home_buyer", StringType()),
      StructField("loan_purpose", StringType()),
      StructField("property_type", StringType()),
      StructField("num_units", IntegerType()),
      StructField("occupancy_status", StringType()),
      StructField("property_state", StringType()),
      StructField("msa", DoubleType()),
      StructField("zip", IntegerType()),
      StructField("mortgage_insurance_percent", DoubleType()),
      StructField("product_type", StringType()),
      StructField("prepayment_penalty_indicator", StringType()),
      StructField("interest_only_loan_indicator", StringType()),
      StructField("interest_only_first_principal_and_interest_payment_date", StringType()),
      StructField("months_to_amortization", StringType()),
      StructField("current_loan_delinquency_status", IntegerType()),
      StructField("loan_payment_history", StringType()),
      StructField("mod_flag", StringType()),
      StructField("mortgage_insurance_cancellation_indicator", StringType()),
      StructField("zero_balance_code", StringType()),
      StructField("zero_balance_effective_date", StringType()),
      StructField("upb_at_the_time_of_removal", StringType()),
      StructField("repurchase_date", StringType()),
      StructField("scheduled_principal_current", StringType()),
      StructField("total_principal_current", StringType()),
      StructField("unscheduled_principal_current", StringType()),
      StructField("last_paid_installment_date", StringType()),
      StructField("foreclosed_after", StringType()),
      StructField("disposition_date", StringType()),
      StructField("foreclosure_costs", DoubleType()),
      StructField("prop_preservation_and_repair_costs", DoubleType()),
      StructField("asset_recovery_costs", DoubleType()),
      StructField("misc_holding_expenses", DoubleType()),
      StructField("holding_taxes", DoubleType()),
      StructField("net_sale_proceeds", DoubleType()),
      StructField("credit_enhancement_proceeds", DoubleType()),
      StructField("repurchase_make_whole_proceeds", StringType()),
      StructField("other_foreclosure_proceeds", DoubleType()),
      StructField("non_interest_bearing_upb", DoubleType()),
      StructField("principal_forgiveness_upb", StringType()),
      StructField("original_list_start_date", StringType()),
      StructField("original_list_price", StringType()),
      StructField("current_list_start_date", StringType()),
      StructField("current_list_price", StringType()),
      StructField("borrower_credit_score_at_issuance", StringType()),
      StructField("co-borrower_credit_score_at_issuance", StringType()),
      StructField("borrower_credit_score_current", StringType()),
      StructField("co-Borrower_credit_score_current", StringType()),
      StructField("mortgage_insurance_type", DoubleType()),
      StructField("servicing_activity_indicator", StringType()),
      StructField("current_period_modification_loss_amount", StringType()),
      StructField("cumulative_modification_loss_amount", StringType()),
      StructField("current_period_credit_event_net_gain_or_loss", StringType()),
      StructField("cumulative_credit_event_net_gain_or_loss", StringType()),
      StructField("homeready_program_indicator", StringType()),
      StructField("foreclosure_principal_write_off_amount", StringType()),
      StructField("relocation_mortgage_indicator", StringType()),
      StructField("zero_balance_code_change_date", StringType()),
      StructField("loan_holdback_indicator", StringType()),
      StructField("loan_holdback_effective_date", StringType()),
      StructField("delinquent_accrued_interest", StringType()),
      StructField("property_valuation_method", StringType()),
      StructField("high_balance_loan_indicator", StringType()),
      StructField("arm_initial_fixed-rate_period_lt_5_yr_indicator", StringType()),
      StructField("arm_product_type", StringType()),
      StructField("initial_fixed-rate_period", StringType()),
      StructField("interest_rate_adjustment_frequency", StringType()),
      StructField("next_interest_rate_adjustment_date", StringType()),
      StructField("next_payment_change_date", StringType()),
      StructField("index", StringType()),
      StructField("arm_cap_structure", StringType()),
      StructField("initial_interest_rate_cap_up_percent", StringType()),
      StructField("periodic_interest_rate_cap_up_percent", StringType()),
      StructField("lifetime_interest_rate_cap_up_percent", StringType()),
      StructField("mortgage_margin", StringType()),
      StructField("arm_balloon_indicator", StringType()),
      StructField("arm_plan_number", StringType()),
      StructField("borrower_assistance_plan", StringType()),
      StructField("hltv_refinance_option_indicator", StringType()),
      StructField("deal_name", StringType()),
      StructField("repurchase_make_whole_proceeds_flag", StringType()),
      StructField("alternative_delinquency_resolution", StringType()),
      StructField("alternative_delinquency_resolution_count", StringType()),
      StructField("total_deferral_amount", StringType())
      ])

# name mappings
_name_mapping = [
        ("WITMER FUNDING, LLC", "Witmer"),
        ("WELLS FARGO CREDIT RISK TRANSFER SECURITIES TRUST 2015", "Wells Fargo"),
        ("WELLS FARGO BANK,  NA" , "Wells Fargo"),
        ("WELLS FARGO BANK, N.A." , "Wells Fargo"),
        ("WELLS FARGO BANK, NA" , "Wells Fargo"),
        ("USAA FEDERAL SAVINGS BANK" , "USAA"),
        ("UNITED SHORE FINANCIAL SERVICES, LLC D\\/B\\/A UNITED WHOLESALE MORTGAGE" , "United Seq(e"),
        ("U.S. BANK N.A." , "US Bank"),
        ("SUNTRUST MORTGAGE INC." , "Suntrust"),
        ("STONEGATE MORTGAGE CORPORATION" , "Stonegate Mortgage"),
        ("STEARNS LENDING, LLC" , "Stearns Lending"),
        ("STEARNS LENDING, INC." , "Stearns Lending"),
        ("SIERRA PACIFIC MORTGAGE COMPANY, INC." , "Sierra Pacific Mortgage"),
        ("REGIONS BANK" , "Regions"),
        ("RBC MORTGAGE COMPANY" , "RBC"),
        ("QUICKEN LOANS INC." , "Quicken Loans"),
        ("PULTE MORTGAGE, L.L.C." , "Pulte Mortgage"),
        ("PROVIDENT FUNDING ASSOCIATES, L.P." , "Provident Funding"),
        ("PROSPECT MORTGAGE, LLC" , "Prospect Mortgage"),
        ("PRINCIPAL RESIDENTIAL MORTGAGE CAPITAL RESOURCES, LLC" , "Principal Residential"),
        ("PNC BANK, N.A." , "PNC"),
        ("PMT CREDIT RISK TRANSFER TRUST 2015-2" , "PennyMac"),
        ("PHH MORTGAGE CORPORATION" , "PHH Mortgage"),
        ("PENNYMAC CORP." , "PennyMac"),
        ("PACIFIC UNION FINANCIAL, LLC" , "Other"),
        ("OTHER" , "Other"),
        ("NYCB MORTGAGE COMPANY, LLC" , "NYCB"),
        ("NEW YORK COMMUNITY BANK" , "NYCB"),
        ("NETBANK FUNDING SERVICES" , "Netbank"),
        ("NATIONSTAR MORTGAGE, LLC" , "Nationstar Mortgage"),
        ("METLIFE BANK, NA" , "Metlife"),
        ("LOANDEPOT.COM, LLC" , "LoanDepot.com"),
        ("J.P. MORGAN MADISON AVENUE SECURITIES TRUST, SERIES 2015-1" , "JP Morgan Chase"),
        ("J.P. MORGAN MADISON AVENUE SECURITIES TRUST, SERIES 2014-1" , "JP Morgan Chase"),
        ("JPMORGAN CHASE BANK, NATIONAL ASSOCIATION" , "JP Morgan Chase"),
        ("JPMORGAN CHASE BANK, NA" , "JP Morgan Chase"),
        ("JP MORGAN CHASE BANK, NA" , "JP Morgan Chase"),
        ("IRWIN MORTGAGE, CORPORATION" , "Irwin Mortgage"),
        ("IMPAC MORTGAGE CORP." , "Impac Mortgage"),
        ("HSBC BANK USA, NATIONAL ASSOCIATION" , "HSBC"),
        ("HOMEWARD RESIDENTIAL, INC." , "Homeward Mortgage"),
        ("HOMESTREET BANK" , "Other"),
        ("HOMEBRIDGE FINANCIAL SERVICES, INC." , "HomeBridge"),
        ("HARWOOD STREET FUNDING I, LLC" , "Harwood Mortgage"),
        ("GUILD MORTGAGE COMPANY" , "Guild Mortgage"),
        ("GMAC MORTGAGE, LLC (USAA FEDERAL SAVINGS BANK)" , "GMAC"),
        ("GMAC MORTGAGE, LLC" , "GMAC"),
        ("GMAC (USAA)" , "GMAC"),
        ("FREMONT BANK" , "Fremont Bank"),
        ("FREEDOM MORTGAGE CORP." , "Freedom Mortgage"),
        ("FRANKLIN AMERICAN MORTGAGE COMPANY" , "Franklin America"),
        ("FLEET NATIONAL BANK" , "Fleet National"),
        ("FLAGSTAR CAPITAL MARKETS CORPORATION" , "Flagstar Bank"),
        ("FLAGSTAR BANK, FSB" , "Flagstar Bank"),
        ("FIRST TENNESSEE BANK NATIONAL ASSOCIATION" , "Other"),
        ("FIFTH THIRD BANK" , "Fifth Third Bank"),
        ("FEDERAL HOME LOAN BANK OF CHICAGO" , "Fedral Home of Chicago"),
        ("FDIC, RECEIVER, INDYMAC FEDERAL BANK FSB" , "FDIC"),
        ("DOWNEY SAVINGS AND LOAN ASSOCIATION, F.A." , "Downey Mortgage"),
        ("DITECH FINANCIAL LLC" , "Ditech"),
        ("CITIMORTGAGE, INC." , "Citi"),
        ("CHICAGO MORTGAGE SOLUTIONS DBA INTERFIRST MORTGAGE COMPANY" , "Chicago Mortgage"),
        ("CHICAGO MORTGAGE SOLUTIONS DBA INTERBANK MORTGAGE COMPANY" , "Chicago Mortgage"),
        ("CHASE HOME FINANCE, LLC" , "JP Morgan Chase"),
        ("CHASE HOME FINANCE FRANKLIN AMERICAN MORTGAGE COMPANY" , "JP Morgan Chase"),
        ("CHASE HOME FINANCE (CIE 1)" , "JP Morgan Chase"),
        ("CHASE HOME FINANCE" , "JP Morgan Chase"),
        ("CASHCALL, INC." , "CashCall"),
        ("CAPITAL ONE, NATIONAL ASSOCIATION" , "Capital One"),
        ("CALIBER HOME LOANS, INC." , "Caliber Funding"),
        ("BISHOPS GATE RESIDENTIAL MORTGAGE TRUST" , "Bishops Gate Mortgage"),
        ("BANK OF AMERICA, N.A." , "Bank of America"),
        ("AMTRUST BANK" , "AmTrust"),
        ("AMERISAVE MORTGAGE CORPORATION" , "Amerisave"),
        ("AMERIHOME MORTGAGE COMPANY, LLC" , "AmeriHome Mortgage"),
        ("ALLY BANK" , "Ally Bank"),
        ("ACADEMY MORTGAGE CORPORATION" , "Academy Mortgage"),
        ("NO CASH-OUT REFINANCE" , "OTHER REFINANCE"),
        ("REFINANCE - NOT SPECIFIED" , "OTHER REFINANCE"),
        ("Other REFINANCE" , "OTHER REFINANCE")]

# String columns
cate_col_names = [
        "orig_channel",
        "first_home_buyer",
        "loan_purpose",
        "property_type",
        "occupancy_status",
        "property_state",
        "product_type",
        "relocation_mortgage_indicator",
        "seller_name",
        "mod_flag"
]
# Numeric columns
label_col_name = "delinquency_12"

numeric_col_names = [
        "orig_interest_rate",
        "orig_upb",
        "orig_loan_term",
        "orig_ltv",
        "orig_cltv",
        "num_borrowers",
        "dti",
        "borrower_credit_score",
        "num_units",
        "zip",
        "mortgage_insurance_percent",
        "current_loan_delinquency_status",
        "current_actual_upb",
        "interest_rate",
        "loan_age",
        "msa",
        "non_interest_bearing_upb",
        label_col_name
]
all_col_names = cate_col_names + numeric_col_names

#-------------------------------------------
# Define the function to do the ETL process
#-------------------------------------------
# Define function to get quarter from input CSV file name
def _get_quarter_from_csv_file_name():
    return substring_index(substring_index(input_file_name(), ".", 1), "/", -1)

# Define function to read raw CSV data file
def read_raw_csv(spark, path):
    return spark.read.format('csv') \
            .option('nullValue', '') \
            .option('header', False) \
            .option('delimiter', '|') \
            .schema(_csv_raw_schema) \
            .load(path) \
            .withColumn('quarter', _get_quarter_from_csv_file_name())

# Functions to extract perf and acq columns from raw schema
def extract_perf_columns(rawDf):
    perfDf = rawDf.select(
      col("loan_id"),
      date_format(to_date(col("monthly_reporting_period"),"MMyyyy"), "MM/dd/yyyy").alias("monthly_reporting_period"),
      upper(col("servicer")).alias("servicer"),
      col("interest_rate"),
      col("current_actual_upb"),
      col("loan_age"),
      col("remaining_months_to_legal_maturity"),
      col("adj_remaining_months_to_maturity"),
      date_format(to_date(col("maturity_date"),"MMyyyy"), "MM/yyyy").alias("maturity_date"),
      col("msa"),
      col("current_loan_delinquency_status"),
      col("mod_flag"),
      col("zero_balance_code"),
      date_format(to_date(col("zero_balance_effective_date"),"MMyyyy"), "MM/yyyy").alias("zero_balance_effective_date"),
      date_format(to_date(col("last_paid_installment_date"),"MMyyyy"), "MM/dd/yyyy").alias("last_paid_installment_date"),
      date_format(to_date(col("foreclosed_after"),"MMyyyy"), "MM/dd/yyyy").alias("foreclosed_after"),
      date_format(to_date(col("disposition_date"),"MMyyyy"), "MM/dd/yyyy").alias("disposition_date"),
      col("foreclosure_costs"),
      col("prop_preservation_and_repair_costs"),
      col("asset_recovery_costs"),
      col("misc_holding_expenses"),
      col("holding_taxes"),
      col("net_sale_proceeds"),
      col("credit_enhancement_proceeds"),
      col("repurchase_make_whole_proceeds"),
      col("other_foreclosure_proceeds"),
      col("non_interest_bearing_upb"),
      col("principal_forgiveness_upb"),
      col("repurchase_make_whole_proceeds_flag"),
      col("foreclosure_principal_write_off_amount"),
      col("servicing_activity_indicator"),
      col('quarter')
    )
    return perfDf.select("*").filter("current_actual_upb != 0.0")

def extract_acq_columns(rawDf):
    acqDf = rawDf.select(
      col("loan_id"),
      col("orig_channel"),
      upper(col("seller_name")).alias("seller_name"),
      col("orig_interest_rate"),
      col("orig_upb"),
      col("orig_loan_term"),
      date_format(to_date(col("orig_date"),"MMyyyy"), "MM/yyyy").alias("orig_date"),
      date_format(to_date(col("first_pay_date"),"MMyyyy"), "MM/yyyy").alias("first_pay_date"),
      col("orig_ltv"),
      col("orig_cltv"),
      col("num_borrowers"),
      col("dti"),
      col("borrower_credit_score"),
      col("first_home_buyer"),
      col("loan_purpose"),
      col("property_type"),
      col("num_units"),
      col("occupancy_status"),
      col("property_state"),
      col("zip"),
      col("mortgage_insurance_percent"),
      col("product_type"),
      col("coborrow_credit_score"),
      col("mortgage_insurance_type"),
      col("relocation_mortgage_indicator"),
      dense_rank().over(Window.partitionBy("loan_id").orderBy(to_date(col("monthly_reporting_period"),"MMyyyy"))).alias("rank"),
      col('quarter')
      )
    return acqDf.select("*").filter(col("rank")==1)

# Define function to parse dates in Performance data
def _parse_dates(perf):
    return perf \
            .withColumn("monthly_reporting_period", to_date(col("monthly_reporting_period"), "MM/dd/yyyy")) \
            .withColumn("monthly_reporting_period_month", month(col("monthly_reporting_period"))) \
            .withColumn("monthly_reporting_period_year", year(col("monthly_reporting_period"))) \
            .withColumn("monthly_reporting_period_day", dayofmonth(col("monthly_reporting_period"))) \
            .withColumn("last_paid_installment_date", to_date(col("last_paid_installment_date"), "MM/dd/yyyy")) \
            .withColumn("foreclosed_after", to_date(col("foreclosed_after"), "MM/dd/yyyy")) \
            .withColumn("disposition_date", to_date(col("disposition_date"), "MM/dd/yyyy")) \
            .withColumn("maturity_date", to_date(col("maturity_date"), "MM/yyyy")) \
            .withColumn("zero_balance_effective_date", to_date(col("zero_balance_effective_date"), "MM/yyyy"))

# Define function to create deliquency dataframe from Performance data
def _create_perf_deliquency(spark, perf):
    aggDF = perf.select(
            col("quarter"),
            col("loan_id"),
            col("current_loan_delinquency_status"),
            when(col("current_loan_delinquency_status") >= 1, col("monthly_reporting_period")).alias("delinquency_30"),
            when(col("current_loan_delinquency_status") >= 3, col("monthly_reporting_period")).alias("delinquency_90"),
            when(col("current_loan_delinquency_status") >= 6, col("monthly_reporting_period")).alias("delinquency_180")) \
            .groupBy("quarter", "loan_id") \
            .agg(
                max("current_loan_delinquency_status").alias("delinquency_12"),
                min("delinquency_30").alias("delinquency_30"),
                min("delinquency_90").alias("delinquency_90"),
                min("delinquency_180").alias("delinquency_180")) \
            .select(
                col("quarter"),
                col("loan_id"),
                (col("delinquency_12") >= 1).alias("ever_30"),
                (col("delinquency_12") >= 3).alias("ever_90"),
                (col("delinquency_12") >= 6).alias("ever_180"),
                col("delinquency_30"),
                col("delinquency_90"),
                col("delinquency_180"))
    joinedDf = perf \
            .withColumnRenamed("monthly_reporting_period", "timestamp") \
            .withColumnRenamed("monthly_reporting_period_month", "timestamp_month") \
            .withColumnRenamed("monthly_reporting_period_year", "timestamp_year") \
            .withColumnRenamed("current_loan_delinquency_status", "delinquency_12") \
            .withColumnRenamed("current_actual_upb", "upb_12") \
            .select("quarter", "loan_id", "timestamp", "delinquency_12", "upb_12", "timestamp_month", "timestamp_year") \
            .join(aggDF, ["loan_id", "quarter"], "left_outer")

    # calculate the 12 month delinquency and upb values
    months = 12
    monthArray = [lit(x) for x in range(0, 12)]
    # explode on a small amount of data is actually slightly more efficient than a cross join
    testDf = joinedDf \
            .withColumn("month_y", explode(array(monthArray))) \
            .select(
                    col("quarter"),
                    floor(((col("timestamp_year") * 12 + col("timestamp_month")) - 24000) / months).alias("josh_mody"),
                    floor(((col("timestamp_year") * 12 + col("timestamp_month")) - 24000 - col("month_y")) / months).alias("josh_mody_n"),
                    col("ever_30"),
                    col("ever_90"),
                    col("ever_180"),
                    col("delinquency_30"),
                    col("delinquency_90"),
                    col("delinquency_180"),
                    col("loan_id"),
                    col("month_y"),
                    col("delinquency_12"),
                    col("upb_12")) \
            .groupBy("quarter", "loan_id", "josh_mody_n", "ever_30", "ever_90", "ever_180", "delinquency_30", "delinquency_90", "delinquency_180", "month_y") \
            .agg(max("delinquency_12").alias("delinquency_12"), min("upb_12").alias("upb_12")) \
            .withColumn("timestamp_year", floor((lit(24000) + (col("josh_mody_n") * lit(months)) + (col("month_y") - 1)) / lit(12))) \
            .selectExpr("*", "pmod(24000 + (josh_mody_n * {}) + month_y, 12) as timestamp_month_tmp".format(months)) \
            .withColumn("timestamp_month", when(col("timestamp_month_tmp") == lit(0), lit(12)).otherwise(col("timestamp_month_tmp"))) \
            .withColumn("delinquency_12", ((col("delinquency_12") > 3).cast("int") + (col("upb_12") == 0).cast("int")).alias("delinquency_12")) \
            .drop("timestamp_month_tmp", "josh_mody_n", "month_y")

    return perf.withColumnRenamed("monthly_reporting_period_month", "timestamp_month") \
            .withColumnRenamed("monthly_reporting_period_year", "timestamp_year") \
            .join(testDf, ["quarter", "loan_id", "timestamp_year", "timestamp_month"], "left") \
            .drop("timestamp_year", "timestamp_month")

# Define function to create acquisition dataframe from Acquisition data
def _create_acquisition(spark, acq):
    nameMapping = spark.createDataFrame(_name_mapping, ["from_seller_name", "to_seller_name"])
    return acq.join(nameMapping, col("seller_name") == col("from_seller_name"), "left") \
      .drop("from_seller_name") \
      .withColumn("old_name", col("seller_name")) \
      .withColumn("seller_name", coalesce(col("to_seller_name"), col("seller_name"))) \
      .drop("to_seller_name") \
      .withColumn("orig_date", to_date(col("orig_date"), "MM/yyyy")) \
      .withColumn("first_pay_date", to_date(col("first_pay_date"), "MM/yyyy"))

# Define function to get column dictionary
def _gen_dictionary(etl_df, col_names):
    cnt_table = etl_df.select(posexplode(array([col(i) for i in col_names])))\
                    .withColumnRenamed("pos", "column_id")\
                    .withColumnRenamed("col", "data")\
                    .filter("data is not null")\
                    .groupBy("column_id", "data")\
                    .count()
    windowed = Window.partitionBy("column_id").orderBy(desc("count"))
    return cnt_table.withColumn("id", row_number().over(windowed)).drop("count")

# Define function to convert string columns to numeric
def _cast_string_columns_to_numeric(spark, input_df):
    cached_dict_df = _gen_dictionary(input_df, cate_col_names).cache()
    output_df = input_df
    #  Generate the final table with all columns being numeric.
    for col_pos, col_name in enumerate(cate_col_names):
        col_dict_df = cached_dict_df.filter(col("column_id") == col_pos)\
                                    .drop("column_id")\
                                    .withColumnRenamed("data", col_name)

        output_df = output_df.join(broadcast(col_dict_df), col_name, "left")\
                        .drop(col_name)\
                        .withColumnRenamed("id", col_name)
    return output_df

# -------------------------------------------
# In this Main Function:

# 1/ Parse date in Performance data by calling _parse_dates (parsed_perf)
# 2/ Create deliqency dataframe(perf_deliqency) form Performance data by calling _create_perf_deliquency
# 3/ Create cleaned acquisition dataframe(cleaned_acq) from Acquisition data by calling _create_acquisition
# 4/ Join deliqency dataframe(perf_deliqency) and cleaned acquisition dataframe(cleaned_acq), get clean_df
# 5/ Cast String column to Numeric in clean_df by calling _cast_string_columns_to_numeric, get casted_clean_df
# 6/ Return casted_clean_df as final result
# -------------------------------------------
def run_mortgage(spark, perf, acq):
    parsed_perf = _parse_dates(perf)
    perf_deliqency = _create_perf_deliquency(spark, parsed_perf)
    cleaned_acq = _create_acquisition(spark, acq)
    clean_df = perf_deliqency.join(cleaned_acq, ["loan_id", "quarter"], "inner").drop("quarter")
    casted_clean_df = _cast_string_columns_to_numeric(spark, clean_df)\
                    .select(all_col_names)\
                    .withColumn(label_col_name, when(col(label_col_name) > 0, 1).otherwise(0))\
                    .fillna(float(0))
    return casted_clean_df

# Read Raw Data and Run ETL Process, Save the Result
rawDf = read_raw_csv(spark, orig_raw_path)
print(f"Raw Dataframe CSV Rows count : {rawDf.count()}")

# Save raw data to parquet
rawDf.write.parquet(orig_raw_path_csv2parquet, mode='overwrite',compression='snappy')

# Read data from parquet
rawDf = spark.read.parquet(orig_raw_path_csv2parquet)
print(f"Raw Dataframe Parquet Rows count : {rawDf.count()}")

acq = extract_acq_columns(rawDf)
perf = extract_perf_columns(rawDf)

# run main function to process data
out = run_mortgage(spark, perf, acq)

# save processed data
if is_save_dataset:
    start = time.time()
    out.write.parquet(output_path_data, mode="overwrite")
    end = time.time()
    print("ETL takes {}".format(end - start))
#-------------------------------------------
# XGBoost Spark with GPU
#-------------------------------------------
# Specify the Data Schema and Load the Data
label = "delinquency_12"
schema = StructType([
    StructField("orig_channel", FloatType()),
    StructField("first_home_buyer", FloatType()),
    StructField("loan_purpose", FloatType()),
    StructField("property_type", FloatType()),
    StructField("occupancy_status", FloatType()),
    StructField("property_state", FloatType()),
    StructField("product_type", FloatType()),
    StructField("relocation_mortgage_indicator", FloatType()),
    StructField("seller_name", FloatType()),
    StructField("mod_flag", FloatType()),
    StructField("orig_interest_rate", FloatType()),
    StructField("orig_upb", DoubleType()),
    StructField("orig_loan_term", IntegerType()),
    StructField("orig_ltv", FloatType()),
    StructField("orig_cltv", FloatType()),
    StructField("num_borrowers", FloatType()),
    StructField("dti", FloatType()),
    StructField("borrower_credit_score", FloatType()),
    StructField("num_units", IntegerType()),
    StructField("zip", IntegerType()),
    StructField("mortgage_insurance_percent", FloatType()),
    StructField("current_loan_delinquency_status", IntegerType()),
    StructField("current_actual_upb", FloatType()),
    StructField("interest_rate", FloatType()),
    StructField("loan_age", FloatType()),
    StructField("msa", FloatType()),
    StructField("non_interest_bearing_upb", FloatType()),
    StructField(label, IntegerType()),
])
features = [ x.name for x in schema if x.name != label ]

if is_save_dataset:
    # load dataset from file
    etlDf = spark.read.parquet(output_path_data)
    splits = etlDf.randomSplit([0.8, 0.2])
    train_data = splits[0]
    test_data = splits[1]
else:
    # use Dataframe from ETL directly
    splits = out.randomSplit([0.8, 0.2])
    train_data = splits[0]
    test_data = splits[1]

train_data.printSchema()

# This sample uses 8 worker(GPU) to run XGBoost training, you can change according to your GPU resources
params = {
    "tree_method": "gpu_hist",
    "grow_policy": "depthwise",
    "num_workers": int(num_workers),
    "device": "cuda",
}
params['features_col'] = features
params['label_col'] = label

classifier = SparkXGBClassifier(**params)

def with_benchmark(phrase, action):
    start = time.time()
    result = action()
    end = time.time()
    print("{} takes {} seconds".format(phrase, end - start))
    return result

# Training time will be printed here
# e.g., Training takes 18.92583155632019 seconds
model = with_benchmark("Training", lambda: classifier.fit(train_data))

model.write().overwrite().save(output_path_model)

loaded_model = SparkXGBClassifierModel().load(output_path_model)

# Transformation time in seconds will be printed here
def transform():
    result = loaded_model.transform(test_data).cache()
    result.foreachPartition(lambda _: None)
    return result

result = with_benchmark("Transformation", transform)

result.select(label, "rawPrediction", "probability", "prediction").show(5)

# Evaluation takes x seconds will be printed here
# Accuracy is x (e.g., 0.9999999999999999)

accuracy = with_benchmark(
    "Evaluation",
    lambda: MulticlassClassificationEvaluator().setLabelCol(label).evaluate(result))

print("Accuracy is " + str(accuracy))

spark.stop()
