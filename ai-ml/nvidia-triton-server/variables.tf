variable "name" {
  description = "Name of the VPC and EKS Cluster"
  default     = "nvidia-triton-server"
  type        = string
}

# NOTE: Trainium and Inferentia are only available in us-west-2 and us-east-1 regions
variable "region" {
  description = "region"
  default     = "us-west-2"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  default     = "1.30"
  type        = string
}

# VPC with 2046 IPs (10.1.0.0/21) and 2 AZs
variable "vpc_cidr" {
  description = "VPC CIDR. This should be a valid private (RFC 1918) CIDR range"
  default     = "10.1.0.0/21"
  type        = string
}

# RFC6598 range 100.64.0.0/10
# Note you can only /16 range to VPC. You can add multiples of /16 if required
variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks to be attached to VPC"
  default     = ["100.64.0.0/16"]
  type        = list(string)
}

# To enable or disable NVIDIA Triton server resources creation
variable "nvidia_triton_server" {
  type = object({
    enable = bool
    repository: string
    tag: string
    model_repository_path = string
    triton_model = string
    enable_huggingface_token = bool
  })
  default = {
      enable = true
      repository: "nvcr.io/nvidia/tritonserver"
      tag: "24.06-vllm-python-py3"//"23.09-py3"
      model_repository_path = "../../gen-ai/inference/nvidia-triton-server-gpu/vllm/model_repository"
      triton_model = "triton-vllm"
      enable_huggingface_token = true
    }
}


#-------------------------------------------------------------------
# Instructions for Securely Setting the Huggingface Token
# -------------------------------------------------------------------
# 1. Obtain your Huggingface token
# 2. Before running 'terraform apply', set the environment variable:
#    * Linux/macOS:
#        export TF_VAR_huggingface_token=<your Huggingface token>
# 3. Now you can safely run 'terraform apply'
#-------------------------------------------------------------------
variable "huggingface_token" {
  description = "Hugging Face Secret Token"
  type        = string
  default     = "DUMMY_TOKEN_REPLACE_ME"
  sensitive   = true
}

variable "enable_nvidia_nim" {
  description = "Toggle to enable or disable NVIDIA NIM pattern resource creation"
  default     = false
  type        = bool
}

#-------------------------------------------------------------------
# Instructions for Securely Setting the NVIDIA NGC API key
# -------------------------------------------------------------------
# 1. Obtain your NVIDIA NGC API key from https://docs.nvidia.com/nim/large-language-models/latest/getting-started.html#generate-an-api-key
# 2. Before running 'terraform apply', set the environment variable:
#    * Linux/macOS:
#        export TF_VAR_ngc_api_key=<your NVIDIA NGC API key>
# 3. Now you can safely run 'terraform apply'
#-------------------------------------------------------------------
variable "ngc_api_key" {
  description = "NGC API Key"
  type        = string
  default     = "DUMMY_NGC_API_KEY_REPLACE_ME"
  sensitive   = true
}
