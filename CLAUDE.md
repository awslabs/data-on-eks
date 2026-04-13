# Project: Data on EKS - Spark Workshop

## Project Context
This is a fork of the AWS Labs data-on-eks repository, specifically working on the `spark-workshop` branch. We're building progressive Spark job examples that demonstrate different optimization techniques.

## Current Work
- **Branch**: `feature/s3-files` (based on `upstream/spark-workshop`)
- **Focus**: Adding S3 Files integration as the latest progression in storage optimization
- **Upstream**: https://github.com/awslabs/data-on-eks.git

## Job Progression Pattern
Each new Spark job builds on the previous one:
1. order-ondemand → order-spot-cmr → order-graviton → order-spot-r → order-nvme → order-s3-files

## Terraform Structure
- **Path**: `analytics/terraform/spark-k8s-operator/`
- **Key files**: 
  - `iam.tf` - IRSA roles for service accounts
  - `addons.tf` - EKS addons (EBS CSI, EFS CSI, Mountpoint S3, etc.)
  - `spark-team.tf` - Team namespaces and service accounts
  - `examples/karpenter/*.yaml` - Spark job manifests

## Conventions
- Use `spark-team-a` namespace for examples
- All Spark jobs read from `s3a://<S3_BUCKET>/order/input/`
- Output goes to `s3a://<S3_BUCKET>/order/output/<job-variant>/`
- Event logs stored at `s3a://<S3_BUCKET>/spark-event-logs`
- Spark image: `public.ecr.aws/data-on-eks/spark:4.0.1-scala2.13-java21-python3-r-ubuntu`

## IAM/IRSA Patterns
- Service accounts use IRSA (IAM Roles for Service Accounts) via OIDC
- All spark teams get S3 access + S3 Tables access by default
- Add new permissions to `data "aws_iam_policy_document" "spark_operator"` in iam.tf

## Git Workflow Preferences
- Create commits with descriptive messages following conventional commits format
- Don't use `git commit --amend` unless explicitly requested
- Always create NEW commits after hook failures
- Stage specific files, not `git add -A`

## Code Style
- Terraform: Use descriptive resource names, add comments for complex logic
- YAML: Include detailed comments explaining purpose and usage
- Create READMEs for new examples explaining architecture and usage

## Testing Approach
- Don't skip verification steps when modifying infrastructure
- Use `terraform plan` before `terraform apply`
- Test Kubernetes manifests with `kubectl apply --dry-run=client` first
