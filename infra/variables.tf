variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "AWS account allowed for this configuration."
  type        = string
  default     = "960410382237"
}

variable "name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "calc"
}

variable "vpc_id" {
  description = "VPC to deploy into (default VPC)."
  type        = string
  default     = "vpc-043897a2ddd934611"
}

variable "subnet_id" {
  description = "Public subnet for the instance (default VPC, us-east-1a)."
  type        = string
  default     = "subnet-02e84cbb6f91489bf"
}

variable "instance_type" {
  description = "EC2 instance type. t2.micro is the free-tier-eligible type in this account."
  type        = string
  default     = "t2.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 8
}

variable "ecr_images_to_keep" {
  description = "Number of images kept in ECR."
  type        = number
  default     = 5
}

variable "github_oidc_subjects" {
  description = <<-EOT
    Allowed GitHub OIDC `sub` claims for the deploy role. This repo uses GitHub's
    immutable subject format (repo:OWNER@OWNER_ID/REPO@REPO_ID:...), which survives
    renames; the legacy name-based format is kept in case the repo setting is reverted.
    Both are pinned to the main branch of zacknaviteq/calc.
  EOT
  type        = list(string)
  default = [
    "repo:zacknaviteq@346338069/calc@1444362044:ref:refs/heads/main",
    "repo:zacknaviteq/calc:ref:refs/heads/main",
  ]
}
