# Need glue a database as a Iceberg Catalog until https://github.com/datahub-project/datahub/issues/14849 is addressed

#---------------------------------------------------------------
# Glue Database for Iceberg Tables
#---------------------------------------------------------------
resource "aws_glue_catalog_database" "data_on_eks" {
  name        = "data_on_eks"
  description = "Database for Data on EKS Iceberg tables"
}
