# Le nom de l'alias du point d'accès S3. 
# (Je pense qu'il s'agit du nom du bucket tel qu'on
# doit le référencer, mais sans certitude..  A tester quand ce sera déployé)
# On garde s3_bucket_id pour éviter trop d'impact sur les appelants
output "s3_bucket_id" {
  value = aws_s3_access_point.this.alias
}