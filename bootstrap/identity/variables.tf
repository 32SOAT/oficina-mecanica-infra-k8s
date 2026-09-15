variable "project_name" {
  description = "Project slug used by stack resources; controllers use a separate terraform name segment."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,29}$", var.project_name))
    error_message = "project_name must be 1–30 lowercase alphanumeric/hyphen characters."
  }
}

variable "aws_region" {
  description = "Commercial AWS region containing the state backend and platform."
  type        = string
  nullable    = false
  validation {
    condition     = contains(keys(local.eks_addon_registry_accounts), var.aws_region)
    error_message = "aws_region must have an official commercial EKS registry in addon-registries.tf; review the AWS registry mapping before adding a new region."
  }
}

variable "aws_account_id" {
  description = "Expected account; also enforced by the AWS provider."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must contain exactly 12 digits."
  }
}

variable "state_bucket_arn" {
  description = "Exact S3 bucket ARN returned by bootstrap/backend."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^arn:aws:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_arn))
    error_message = "state_bucket_arn must be an exact bucket ARN without wildcard or object suffix."
  }
}

variable "state_kms_key_arn" {
  description = "Exact backend KMS key ARN in this account and region; its policy delegates usage through account IAM."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^arn:aws:kms:${var.aws_region}:${var.aws_account_id}:key/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$", var.state_kms_key_arn))
    error_message = "state_kms_key_arn must be an exact KMS key ARN in aws_account_id and aws_region."
  }
}

variable "github_organization" {
  description = "Approved GitHub organization; changing ownership requires an explicit code review."
  type        = string
  default     = "32SOAT"
  nullable    = false
  validation {
    condition     = var.github_organization == "32SOAT"
    error_message = "Only the approved 32SOAT organization is supported."
  }
}

variable "github_repository" {
  description = "Approved infrastructure repository; never a wildcard or application repository."
  type        = string
  default     = "oficina-mecanica-infra-k8s"
  nullable    = false
  validation {
    condition     = var.github_repository == "oficina-mecanica-infra-k8s"
    error_message = "Only oficina-mecanica-infra-k8s may assume Terraform roles."
  }
}

variable "tags" {
  description = "Additional tags for bootstrap identities."
  type        = map(string)
  default     = {}
  nullable    = false
}
