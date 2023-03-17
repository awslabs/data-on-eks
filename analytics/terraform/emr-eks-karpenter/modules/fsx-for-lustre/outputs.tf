
output "aws_fsx_lustre_file_system_arn" {
  description = "Amazon Resource Name of the file system"
  value       = aws_fsx_lustre_file_system.this.arn
}

output "aws_fsx_lustre_file_system_id" {
  description = "Identifier of the file system, e.g., fs-12345678"
  value       = aws_fsx_lustre_file_system.this.id
}

output "aws_fsx_lustre_file_system_dns_name" {
  description = "DNS name for the file system, e.g., fs-12345678.fsx.us-west-2.amazonaws.com"
  value       = aws_fsx_lustre_file_system.this.dns_name
}

output "aws_fsx_lustre_file_system_mount_name" {
  description = "The value to be used when mounting the filesystem"
  value       = aws_fsx_lustre_file_system.this.mount_name
}

output "aws_fsx_lustre_file_system_owner_id" {
  description = "AWS account identifier that created the file system"
  value       = aws_fsx_lustre_file_system.this.owner_id
}
