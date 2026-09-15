# Removing encryption, recovery controls, TLS enforcement, or narrowing validation
# incorrectly must fail these checks. Only provider I/O is mocked; policies are real.
mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:role/infra-admin"
      user_id    = "AROAEXAMPLE:operator"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      id  = "oficina-mecanica-tfstate-123456789012"
      arn = "arn:aws:s3:::oficina-mecanica-tfstate-123456789012"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
      key_id = "11111111-2222-3333-4444-555555555555"
    }
  }
}

variables {
  project_name            = "oficina-mecanica"
  aws_region              = "us-east-1"
  administrator_role_arns = ["arn:aws:iam::123456789012:role/infra-admin"]
  tags                    = { CostCenter = "platform" }
}

run "backend_is_recoverable_and_private" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state.bucket == "oficina-mecanica-tfstate-123456789012" && !aws_s3_bucket.state.force_destroy
    error_message = "State bucket must be account-scoped and reject forced destruction."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.bucket == aws_s3_bucket.state.id && aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "The state bucket must retain object versions."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.state.bucket == aws_s3_bucket.state.id &&
      aws_s3_bucket_public_access_block.state.block_public_acls &&
      aws_s3_bucket_public_access_block.state.ignore_public_acls &&
      aws_s3_bucket_public_access_block.state.block_public_policy &&
      aws_s3_bucket_public_access_block.state.restrict_public_buckets
    )
    error_message = "All four public access protections must cover the state bucket."
  }

  assert {
    condition = (
      aws_s3_bucket_server_side_encryption_configuration.state.bucket == aws_s3_bucket.state.id &&
      one(aws_s3_bucket_server_side_encryption_configuration.state.rule).bucket_key_enabled &&
      one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms" &&
      one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default[0].kms_master_key_id == aws_kms_key.state.arn
    )
    error_message = "State must use the dedicated KMS key with S3 bucket keys."
  }

  assert {
    condition     = aws_kms_key.state.enable_key_rotation && aws_kms_key.state.deletion_window_in_days == 30
    error_message = "The state key needs rotation and a recovery window before deletion."
  }

  assert {
    condition = (
      aws_s3_bucket_lifecycle_configuration.state.bucket == aws_s3_bucket.state.id &&
      one(aws_s3_bucket_lifecycle_configuration.state.rule).status == "Enabled" &&
      one(aws_s3_bucket_lifecycle_configuration.state.rule).noncurrent_version_expiration[0].noncurrent_days >= 90 &&
      one(aws_s3_bucket_lifecycle_configuration.state.rule).noncurrent_version_expiration[0].newer_noncurrent_versions >= 10 &&
      length(one(aws_s3_bucket_lifecycle_configuration.state.rule).expiration) == 0
    )
    error_message = "Retain at least 90 days and 10 prior versions without expiring the current state."
  }

  assert {
    condition = (
      output.state_bucket_name == aws_s3_bucket.state.bucket &&
      output.state_bucket_arn == aws_s3_bucket.state.arn &&
      output.state_kms_key_arn == aws_kms_key.state.arn &&
      aws_kms_alias.state.target_key_id == aws_kms_key.state.key_id
    )
    error_message = "Backend outputs and alias must reference the managed bucket and key."
  }

  assert {
    condition     = aws_s3_bucket.state.tags["CostCenter"] == "platform" && aws_kms_key.state.tags["CostCenter"] == "platform"
    error_message = "Caller tags must reach the state bucket and key."
  }
}

run "state_policy_denies_plaintext_transport" {
  command = plan

  assert {
    condition = (
      aws_s3_bucket_policy.state.bucket == aws_s3_bucket.state.id &&
      length(jsondecode(aws_s3_bucket_policy.state.policy).Statement) == 1 &&
      one(jsondecode(aws_s3_bucket_policy.state.policy).Statement).Effect == "Deny" &&
      one(jsondecode(aws_s3_bucket_policy.state.policy).Statement).Principal == "*" &&
      one(jsondecode(aws_s3_bucket_policy.state.policy).Statement).Action == "s3:*" &&
      toset(one(jsondecode(aws_s3_bucket_policy.state.policy).Statement).Resource) == toset([aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]) &&
      one(jsondecode(aws_s3_bucket_policy.state.policy).Statement).Condition.Bool["aws:SecureTransport"] == "false"
    )
    error_message = "Deny all non-TLS bucket and object operations for every principal; no public Allow."
  }
}

run "kms_separates_administration_from_account_iam_usage" {
  command = plan

  assert {
    condition = (
      length(jsondecode(aws_kms_key.state.policy).Statement) == 2 &&
      alltrue([for statement in jsondecode(aws_kms_key.state.policy).Statement : statement.Effect == "Allow" && statement.Resource == "*"]) &&
      toset(jsondecode(aws_kms_key.state.policy).Statement[0].Principal.AWS) == toset(["arn:aws:iam::123456789012:role/infra-admin"]) &&
      contains(jsondecode(aws_kms_key.state.policy).Statement[0].Action, "kms:PutKeyPolicy") &&
      contains(jsondecode(aws_kms_key.state.policy).Statement[0].Action, "kms:ScheduleKeyDeletion") &&
      !contains(jsondecode(aws_kms_key.state.policy).Statement[0].Action, "kms:*") &&
      !contains(jsondecode(aws_kms_key.state.policy).Statement[0].Action, "kms:Decrypt")
    )
    error_message = "Only the supplied role ARNs may explicitly administer the key."
  }

  assert {
    condition = (
      jsondecode(aws_kms_key.state.policy).Statement[1].Principal.AWS == "arn:aws:iam::123456789012:root" &&
      toset(jsondecode(aws_kms_key.state.policy).Statement[1].Action) == toset(["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]) &&
      jsondecode(aws_kms_key.state.policy).Statement[1].Condition.StringEquals["kms:CallerAccount"] == "123456789012" &&
      jsondecode(aws_kms_key.state.policy).Statement[1].Condition.StringEquals["kms:ViaService"] == "s3.us-east-1.amazonaws.com"
    )
    error_message = "Delegate only key usage through same-account IAM and S3, allowing future roles without circular references."
  }
}

run "reject_invalid_project_name" {
  command = plan
  variables { project_name = "Invalid_Project" }
  expect_failures = [var.project_name]
}

run "reject_project_name_exceeding_bucket_limit" {
  command = plan
  variables { project_name = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopq" }
  expect_failures = [var.project_name]
}

run "reject_empty_administrators" {
  command = plan
  variables { administrator_role_arns = [] }
  expect_failures = [var.administrator_role_arns]
}

run "reject_wildcard_administrator" {
  command = plan
  variables { administrator_role_arns = ["*"] }
  expect_failures = [var.administrator_role_arns]
}

run "reject_external_administrator" {
  command = plan
  variables { administrator_role_arns = ["arn:aws:iam::210987654321:role/external-admin"] }
  expect_failures = [var.administrator_role_arns]
}

run "reject_invalid_region" {
  command = plan
  variables { aws_region = "not-a-region" }
  expect_failures = [var.aws_region]
}
