# calc app in the AWS Check account (899796413445, eu-north-1):
# one EC2 instance with Docker behind an Elastic IP, port 80 open only to
# var.allowed_http_cidrs (empty by default: closed to the internet),
# SSM-only access (no SSH), and an S3 bucket for deploy artifacts.

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  name             = "calc"
  artifacts_bucket = "calc-deploy-artifacts-${var.account_id}"
}

# ---------------------------------------------------------------------------
# Deploy artifacts (tarballs of the repo uploaded by the pipeline)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "artifacts" {
  bucket = local.artifacts_bucket
}

resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"
    filter {}
    expiration {
      days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# ---------------------------------------------------------------------------
# Network: HTTP only from var.allowed_http_cidrs (none by default), no SSH
# ---------------------------------------------------------------------------
resource "aws_security_group" "web" {
  name        = "${local.name}-web"
  description = "HTTP to the calc app. No SSH; use SSM Session Manager."
  vpc_id      = var.vpc_id
  tags        = { Name = "${local.name}-web" }
}

# Access from the internet is blocked: no ingress rule exists unless a CIDR
# is added to var.allowed_http_cidrs (e.g. ["203.0.113.10/32"]).
resource "aws_vpc_security_group_ingress_rule" "http_allowed" {
  for_each = toset(var.allowed_http_cidrs)

  security_group_id = aws_security_group.web.id
  description       = "HTTP from an allowed network"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.web.id
  description       = "Outbound for SSM, S3, GitHub and Docker Hub"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------------------
# Instance role: SSM Run Command / Session Manager + read deploy artifacts
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "calc-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "instance_artifacts" {
  statement {
    sid       = "ReadDeployArtifacts"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }
}

resource "aws_iam_role_policy" "instance_artifacts" {
  name   = "read-deploy-artifacts"
  role   = aws_iam_role.instance.name
  policy = data.aws_iam_policy_document.instance_artifacts.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "calc-instance"
  role = aws_iam_role.instance.name
}

# ---------------------------------------------------------------------------
# App instance + Elastic IP
# ---------------------------------------------------------------------------
resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  monitoring             = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    region   = var.region
    git_repo = var.git_repo_url
  })
  user_data_replace_on_change = true

  lifecycle {
    # Don't replace the instance when AWS publishes a new AL2023 AMI.
    ignore_changes = [ami]
  }

  tags = { Name = "calc-app" }
}

resource "aws_eip" "app" {
  domain   = "vpc"
  instance = aws_instance.app.id
  tags     = { Name = "calc-app" }
}
