# Steps to deploy the blupeprint
  1. Run the terraform script

   ``` 
    terraform init

    terraform apply
  ```
  1. Edit the basic-example-app-cluster.yaml to use your **own** S3 bucket url
  2. Deploy a sample job to run a Flink job
   ```
   kubectl apply -f basic-example-app-cluster.yaml
   ```



    