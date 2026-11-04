output "public_ip" {
  description = "Elastic IP of the app instance."
  value       = aws_eip.app.public_ip
}

output "app_url" {
  description = "Public URL of the calculator."
  value       = "http://${aws_eip.app.public_ip}/"
}

output "instance_id" {
  description = "EC2 instance ID (repo variable EC2_INSTANCE_ID)."
  value       = aws_instance.app.id
}

output "ecr_repository" {
  description = "ECR repository name (repo variable ECR_REPOSITORY)."
  value       = aws_ecr_repository.calc.name
}

output "ecr_repository_url" {
  description = "ECR repository URL."
  value       = aws_ecr_repository.calc.repository_url
}

output "github_deploy_role_arn" {
  description = "Deploy role ARN (repo variable AWS_ROLE_ARN)."
  value       = aws_iam_role.github_deploy.arn
}

output "hardened_images_repository_url" {
  description = "ECR repository URL for hardened images."
  value       = aws_ecr_repository.hardened_images.repository_url
}

output "hardening_evidence_bucket" {
  description = "S3 bucket for hardening evidence (repo variable HARDEN_EVIDENCE_BUCKET)."
  value       = aws_s3_bucket.hardening_evidence.bucket
}

output "github_harden_role_arn" {
  description = "Hardening workflow role ARN (repo variable HARDEN_ROLE_ARN)."
  value       = aws_iam_role.github_harden.arn
}
