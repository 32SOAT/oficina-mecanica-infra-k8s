data "aws_caller_identity" "current" {}

locals {
  state_bucket_name = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"
  tags = merge(var.tags, {
    Project   = var.project_name
    ManagedBy = "Terraform"
    Component = "remote-state"
  })
}

resource "aws_kms_key" "state" {
  description             = "Remote Terraform state encryption for ${var.project_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags

  # jsonencode keeps policy evaluation local, including during mock-provider tests.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ExplicitKeyAdministrators"
        Effect    = "Allow"
        Principal = { AWS = sort(tolist(var.administrator_role_arns)) }
        Action = [
          "kms:DescribeKey",
          "kms:GetKeyPolicy",
          "kms:PutKeyPolicy",
          "kms:ListKeyPolicies",
          "kms:EnableKey",
          "kms:DisableKey",
          "kms:UpdateKeyDescription",
          "kms:EnableKeyRotation",
          "kms:DisableKeyRotation",
          "kms:GetKeyRotationStatus",
          "kms:RotateKeyOnDemand",
          "kms:ListKeyRotations",
          "kms:TagResource",
          "kms:UntagResource",
          "kms:ListResourceTags",
          "kms:CreateAlias",
          "kms:UpdateAlias",
          "kms:DeleteAlias",
          "kms:ScheduleKeyDeletion",
          "kms:CancelKeyDeletion",
        ]
        Resource = "*"
      },
      {
        # Account-root here enables IAM delegation, not an unconditional grant
        # to every role. Task 6 grants scoped usage in the future roles' IAM policies.
        Sid       = "DelegateStateUsageToAccountIAM"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
            "kms:ViaService"    = "s3.${var.aws_region}.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.project_name}-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket" "state" {
  bucket        = local.state_bucket_name
  force_destroy = false
  tags          = local.tags
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket     = aws_s3_bucket.state.id
  depends_on = [aws_s3_bucket_versioning.state]

  rule {
    id     = "retain-recoverable-state-versions"
    status = "Enabled"

    filter {
      prefix = ""
    }

    # Both conditions must be met: at least 90 days old and beyond the last 10.
    # The current version never expires, including rarely updated bootstrap state.
    noncurrent_version_expiration {
      noncurrent_days           = 90
      newer_noncurrent_versions = 10
    }
  }
}
