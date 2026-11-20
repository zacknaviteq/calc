output "public_ip" {
  description = "Elastic IP of the calc app."
  value       = aws_eip.app.public_ip
}

output "app_url" {
  description = "Public URL of the calculator."
  value       = "http://${aws_eip.app.public_ip}/"
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.app.id
}

output "artifacts_bucket" {
  description = "S3 bucket for deploy artifacts."
  value       = aws_s3_bucket.artifacts.bucket
}
