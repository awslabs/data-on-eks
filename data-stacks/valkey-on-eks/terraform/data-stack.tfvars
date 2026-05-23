name                 = "valkey-on-eks"
region               = "us-west-2"
enable_ingress_nginx = false
enable_valkey        = true

# Unique ID used to tag all AWS resources for this deployment.
# Enables identification of orphaned resources and cleanup in case of Terraform state loss.
# Auto-generated on first deploy — do not edit manually.
deployment_id   = "DO-NOT-EDIT-AUTO-GENERATED"
