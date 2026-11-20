variable "region" {
  description = "AWS region of the AWS Check account."
  type        = string
  default     = "eu-north-1"
}

variable "account_id" {
  description = "AWS Check account."
  type        = string
  default     = "899796413445"
}

variable "vpc_id" {
  description = "Default VPC of the account."
  type        = string
  default     = "vpc-03da90e3a186fa6be"
}

variable "subnet_id" {
  description = "Public subnet of the default VPC (eu-north-1b)."
  type        = string
  default     = "subnet-0c396858a4131ed87"
}

variable "instance_type" {
  description = "EC2 instance type (Graviton, arm64)."
  type        = string
  default     = "t4g.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 8
}

variable "git_repo_url" {
  description = "Public git repository the instance builds the first version from."
  type        = string
  default     = "https://github.com/zacknaviteq/calc.git"
}

variable "allowed_http_cidrs" {
  description = "IPv4 CIDRs allowed to reach the app on port 80. Empty = blocked from the internet. Never add 0.0.0.0/0 here to keep it private."
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.allowed_http_cidrs, "0.0.0.0/0")
    error_message = "0.0.0.0/0 would open the app to the whole internet."
  }
}
