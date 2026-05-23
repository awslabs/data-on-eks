region               = "us-west-2"
enable_ingress_nginx = true
# Unique ID used to tag all AWS resources for this deployment.
# Enables identification of orphaned resources and cleanup in case of Terraform state loss.
# Auto-generated on first deploy — do not edit manually.
deployment_id   = "DO-NOT-EDIT-AUTO-GENERATED"
enable_datahub  = true
enable_superset = true
enable_celeborn = true
