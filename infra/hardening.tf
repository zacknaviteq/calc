# ---------------------------------------------------------------------------
# STIG/FIPS hardening pipeline (.github/workflows/harden.yml)
#   calc (ECR) -> rebuild on UBI 9 -> hardened-images (ECR) + evidence (S3)
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "hardened_images" {
  name = "hardened-images"

  # Image tags are immutable. cosign's legacy fallback tags (sha256-<digest>.sig/.att)
  # are re-pointed when signatures/attestations are added, so they are excluded.
  image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"

  image_tag_mutability_exclusion_filter {
    filter      = "sha256-*"
    filter_type = "WILDCARD"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "hardened_images" {
  repository = aws_ecr_repository.hardened_images.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last ${var.hardened_images_to_keep} hardened images"
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = ["calc-"]
        countType     = "imageCountMoreThan"
        countNumber   = var.hardened_images_to_keep
      }
      action = { type = "expire" }
    }]
  })
}

# ---------------------------------------------------------------------------
# Evidence bucket (WORM: Object Lock, governance mode)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "hardening_evidence" {
  bucket              = "${var.name}-hardening-evidence-${var.account_id}"
  object_lock_enabled = true
}

resource "aws_s3_bucket_ownership_controls" "hardening_evidence" {
  bucket = aws_s3_bucket.hardening_evidence.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "hardening_evidence" {
  bucket                  = aws_s3_bucket.hardening_evidence.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "hardening_evidence" {
  bucket = aws_s3_bucket.hardening_evidence.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "hardening_evidence" {
  bucket = aws_s3_bucket.hardening_evidence.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_object_lock_configuration" "hardening_evidence" {
  bucket = aws_s3_bucket.hardening_evidence.id
  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.evidence_retention_days
    }
  }
  depends_on = [aws_s3_bucket_versioning.hardening_evidence]
}

resource "aws_s3_bucket_lifecycle_configuration" "hardening_evidence" {
  bucket = aws_s3_bucket.hardening_evidence.id

  rule {
    id     = "archive-evidence"
    status = "Enabled"
    filter {}

    transition {
      days          = var.evidence_glacier_after_days
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = var.evidence_glacier_after_days
      storage_class   = "GLACIER"
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.hardening_evidence]
}

data "aws_iam_policy_document" "hardening_evidence_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.hardening_evidence.arn,
      "${aws_s3_bucket.hardening_evidence.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "hardening_evidence" {
  bucket     = aws_s3_bucket.hardening_evidence.id
  policy     = data.aws_iam_policy_document.hardening_evidence_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.hardening_evidence]
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC role for the hardening workflow.
# Same trust as the deploy role (main branch of zacknaviteq/calc only).
# ---------------------------------------------------------------------------
resource "aws_iam_role" "github_harden" {
  name                 = "${var.name}-github-harden"
  assume_role_policy   = data.aws_iam_policy_document.github_assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "github_harden" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPullCalc"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]
    resources = [aws_ecr_repository.calc.arn]
  }

  statement {
    sid = "EcrPushHardened"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
      "ecr:ListImages",
      "ecr:ListImageReferrers",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
    ]
    resources = [aws_ecr_repository.hardened_images.arn]
  }

  statement {
    sid       = "PutEvidence"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.hardening_evidence.arn}/*"]
  }
}

resource "aws_iam_role_policy" "github_harden" {
  name   = "harden"
  role   = aws_iam_role.github_harden.id
  policy = data.aws_iam_policy_document.github_harden.json
}
