terraform {
  backend "s3" {
    bucket         = "tf-backend-012046422670"
    key            = "terraform/state-route53-poc"
    region         = "us-west-2"
    dynamodb_table = "tf-backend-012046422670"
    encrypt        = true
  }
  # backend "local" {
  #   path = "terraform.tfstate"
  # }
}