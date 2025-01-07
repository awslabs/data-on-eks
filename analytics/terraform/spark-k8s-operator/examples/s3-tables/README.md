# S3Table with OSS Spark on EKS Guide


## Step1: Create Test Data for the job
    
    Run this script locally `./input-data-gen.sh`. this will create a file called `employee_data.csv` locally with 100 records

## Step2: Copy this input data to S3 bucket created by this bluprint. 

    ```sh
    aws s3 cp employee_data.csv s3://<S3_BUCKET>/s3table-example/input/
    ```

# Step3: Copy PySpark script to S3 bucket

    ```sh
    aws s3 cp s3table-iceberg-pyspark.py s3://<S3_BUCKET>/s3table-example/scripts/
    ```

# Step4: Create S3Table

    ```sh

    ```

# Step5: Update Spark Operator YAML File

 - Open `s3table-spark-operator.yaml` file
 - Replace `<S3_BUCKET>` with your S3 bucket created by this blueprint(Check Terraform outputs)
 - REPLACE `<S3TABLE_ARN>` with actaul S3 Table ARN

# Step6: Execute Spark Job

    ```sh
    kubectl apply -f s3table-spark-operator.yaml
    ```
# Step7: Verify the Spark Driver log for the output


