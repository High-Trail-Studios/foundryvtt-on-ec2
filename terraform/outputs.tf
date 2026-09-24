output "instance_id" {
  description = "EC2 instance ID. Start and stop it with this."
  value       = aws_instance.foundry.id
}

output "region" {
  description = "Region the stack is deployed in."
  value       = var.aws_region
}

output "bucket" {
  description = "S3 bucket. Upload the Foundry zip to the dist/ prefix here."
  value       = aws_s3_bucket.data.id
}

output "foundry_zip_destination" {
  description = "Exact destination for the Foundry download before first start."
  value       = "s3://${aws_s3_bucket.data.id}/dist/FoundryVTT-Node-${var.foundry_version}.zip"
}

output "ecr_repository_url" {
  description = "ECR repository. The instance builds and pushes here itself (R13)."
  value       = aws_ecr_repository.foundry.repository_url
}

output "url" {
  description = "Where Foundry will be served once the instance is started."
  value       = "https://${var.domain_name}"
}

output "data_volume_id" {
  description = "Persistent data volume. Protected by prevent_destroy — see REQUIREMENTS.md R15 before tearing down."
  value       = aws_ebs_volume.data.id
}

output "start_command" {
  description = "Start the instance for a session."
  value       = "aws ec2 start-instances --region ${var.aws_region} --instance-ids ${aws_instance.foundry.id}"
}

output "stop_command" {
  description = "Stop it afterwards. This is what keeps the bill near zero."
  value       = "aws ec2 stop-instances --region ${var.aws_region} --instance-ids ${aws_instance.foundry.id}"
}

output "logs_command" {
  description = "Watch the boot sequence. Requires the SSM plugin."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.foundry.id}"
}
