locals {
emr_eks_virtual_cluster_id = var.virtual_cluster_id
emr_eks_job_execution_role_arn = var.job_execution_role_arn
s3_bucket_id = var.s3_bucket_id

  definition_template = <<EOF
      {
      "Comment": "Statefunction Job with EMR on EKS",
      "StartAt": "EMR-on-EKS StartJobRun",
      "States": {
        "EMR-on-EKS StartJobRun": {
          "Type": "Task",
          "Resource": "arn:aws:states:::emr-containers:startJobRun.sync",
          "Parameters": {
            "VirtualClusterId": "${local.emr_eks_virtual_cluster_id}",
            "ExecutionRoleArn": "${local.emr_eks_job_execution_role_arn}",
            "ReleaseLabel": "emr-6.7.0-latest",
            "JobDriver": {
              "SparkSubmitJobDriver": {
                "EntryPoint": "s3://${local.s3_bucket_id}/scripts/spark-etl.py",
                "EntryPointArguments": ["s3://${local.s3_bucket_id}/shared_datasets/tripdata/",
                "s3://${local.s3_bucket_id}/data_output/"],
                "SparkSubmitParameters": "--conf spark.executors.instances=2 --conf spark.executors.memory=2G --conf spark.executor.cores=2 --conf spark.driver.cores=1"
              }
            }
          },
          "End": true
        }
      }
    }
  
    EOF
  }


module "step-functions" {
  source  = "terraform-aws-modules/step-functions/aws"
  version = "2.7.3"
  name = "EMR_EKS_STEP_FUNCTION"
  definition = local.definition_template
  
  logging_configuration = {
    include_execution_data = true
    level                  = "ALL"
  }
  
  role_name = "EMR_EKS_StepFn_Role"
  attach_policy_json = true
  policy_json        = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "emr-containers:*",
                "s3:*"
            ],
            "Resource": ["*"]
        }
    ]
}
EOF
  

}