#import aws provider
provider "aws" {
  region = "us-west-2"
}
provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}
provider "kubernetes" {
  config_path = "~/.kube/config"

}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}
