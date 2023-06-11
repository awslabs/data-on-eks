# Submitting a XGBoost-PySpark job

## Create custom Docker image

Assuming that you are in the `emr-spark-rapids` folder as <ROOT> and we are using us-west-2 as the example region

```
$ cd <ROOT>/examples/xgboost

# Login to the ECR in us-west-2 to download the Spark Rapids EMR on EKS image.
# If you are in a different region, refer to: https://docs.aws.amazon.com/emr/latest/EMR-on-EKS-DevelopmentGuide/docker-custom-images-tag.html

$ aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin 895885662937.dkr.ecr.us-west-2.amazonaws.com

# Change the tag as preferred; using 0.10 as the tag example here

$ docker build -t < ACCOUNT ID >.dkr.ecr.us-west-2.amazonaws.com/emr-6.10.0-spark-rapids:0.10 -f Dockerfile .

# After the docker image has been created

$ aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin < ACCOUNT ID >.dkr.ecr.us-west-2.amazonaws.com

$ docker push < ACCOUNT ID >.dkr.ecr.us-west-2.amazonaws.com/emr-6.10.0-spark-rapids:0.10

```

## Configuring your pod templates

- Assuming that you are using us-west-2 as the region, the only change to the pod templates (driver-pod-template.yaml and executor-pod-template.yaml) required is to give your job name and replace `<job_name>`

```
metadata:
  name: <job_name>-driver
```
## Download Nvidia JAR files from Maven

```
$ curl -O https://repo1.maven.org/maven2/com/nvidia/xgboost4j-spark_3.0/1.4.2-0.3.0/xgboost4j-spark_3.0-1.4.2-0.3.0.jar
$ curl -O https://repo1.maven.org/maven2/com/nvidia/xgboost4j_3.0/1.4.2-0.3.0/xgboost4j_3.0-1.4.2-0.3.0.jar
```

## Upload the files to S3

```
export BUCKET_NAME="< BUCKET NAME >"

# Upload the JAR files

$ aws s3 cp xgboost4j-spark_3.0-1.4.2-0.3.0.jar s3://< BUCKET NAME >/nvidia/
$ aws s3 cp xgboost4j_3.0-1.4.2-0.3.0.jar s3://< BUCKET NAME >/nvidia/

# Upload the pod templates

$ aws s3 cp driver-pod-template.yaml s3://< BUCKET NAME >/nvidia/pod-templates/
$ aws s3 cp executor-pod-template.yaml s3://< BUCKET NAME >/nvidia/pod-templates/

# Upload the Python script

$ aws cp etl-xgboost-train-transform-us-west-2.py s3://< BUCKET NAME >/scripts/nvidia/etl-xgboost-train-transform-us-west-2.py
```

## Download the required data from Fannie Mae

- Dataset is derived from [Fannie Mae’s Single-Family Loan Performance Data](http://www.fanniemae.com/portal/funding-the-market/data/loan-performance-data.html) with all rights reserved by Fannie Mae. Refer to these [instructions](https://github.com/NVIDIA/spark-rapids-examples/blob/branch-23.04/docs/get-started/xgboost-examples/dataset/mortgage.md) to download the dataset.
- **IMPORTANT**: Download the data and UPLOAD the data files into a bucket and in any prefix but ensure that the last prefix is `fannie-mae-single-family-loan-performance/`. Example:
```
s3://< BUCKET NAME >/emr-eks-xgboost-gpu/data/fannie-mae-single-family-loan-performance/
```

### How to download the Mortgage dataset

#### Steps to download the data

1. Go to the [Fannie Mae](https://capitalmarkets.fanniemae.com/credit-risk-transfer/single-family-credit-risk-transfer/fannie-mae-single-family-loan-performance-data) website
2. Click on [Single-Family Loan Performance Data](https://datadynamics.fanniemae.com/data-dynamics/?&_ga=2.181456292.2043790680.1657122341-289272350.1655822609#/reportMenu;category=HP)
    * Register as a new user if you are using the website for the first time
    * Use the credentials to login
3. Select [HP](https://datadynamics.fanniemae.com/data-dynamics/#/reportMenu;category=HP)
4. Click on  **Download Data** and choose *Single-Family Loan Performance Data*
5. You will find a tabular list of 'Acquisition and Performance' files sorted based on year and quarter. Click on the file to download `Eg: 2017Q1.zip`
6. Unzip the downlad file to extract the csv file `Eg: 2017Q1.csv`
7. Copy only the csv files to a new folder for the ETL to read

#### Notes
1. Refer to the [Loan Performance Data Tutorial](https://capitalmarkets.fanniemae.com/media/9066/display) for more details.
2. Note that *Single-Family Loan Performance Data* has 2 componenets. However, the Mortgage ETL requires only the first one (primary dataset)
    * Primary Dataset:  Acquisition and Performance Files
    * HARP Dataset
3. Use the [Resources](https://datadynamics.fanniemae.com/data-dynamics/#/resources/HP) section to know more about the dataset
4.

## Modify the xgboost-spark-job.json

### **NOTE**: This section will be changed to use a wrapper script to generate the JSON file

- Look through the JSON file carefully and replace any variables ( example: < BUCKET NAME > ).
- As long as the script, pod templates, and JAR files are uploaded in the same prefix structure as outlined in the above section, only the BUCKET_NAME and DATA_ROOT_PREFIX needs to be changed for these entities.
- For the IAM Role for the Job execution, modify the Account ID. If running in namespace `emr-ml-team-a`, the IAM role name need not be changed.
- If running in the namespace as emr-ml-team-a, find the EMR Virtual Cluster ID for `emr-spark-rapids-emr-ml-team-a`. Modify as necessary for another team.
- Save the JSON file
-
## Submit the job

$ aws emr-containers start-job-run --cli-input-json file://xgboost-spark-job.json --region us-west-2
