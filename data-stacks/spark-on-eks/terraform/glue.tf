# Iceberg uses a Glue database as catalog until https://github.com/datahub-project/datahub/issues/14849 is fixed.

resource "aws_glue_catalog_database" "data_on_eks" {
  name        = replace(local.name, "-", "_")
  description = "Database for ${local.name} Iceberg tables"
}
