name                 = "ray-on-eks"
region               = "us-west-2"
enable_ingress_nginx = true
enable_raydata       = true

# Unique ID used to tag all AWS resources for this deployment.
# Enables identification of orphaned resources and cleanup in case of Terraform state loss.
# Auto-generated on first deploy — do not edit manually.
deployment_id = "DO-NOT-EDIT-AUTO-GENERATED"
