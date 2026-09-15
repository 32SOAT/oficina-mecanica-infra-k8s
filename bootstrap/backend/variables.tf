variable "project_name" {
  description = "Lowercase project slug; leaves room for the state suffix and account ID in the S3 bucket name."
  type        = string
  nullable    = false

  validation {
    condition = (
      length(var.project_name) >= 1 && length(var.project_name) <= 42 &&
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.project_name)) &&
      !startswith(var.project_name, "xn--") &&
      !startswith(var.project_name, "sthree-") &&
      !startswith(var.project_name, "amzn-s3-demo-")
    )
    error_message = "project_name must be 1–42 lowercase alphanumeric/hyphen characters, start/end alphanumeric, and avoid S3 reserved prefixes."
  }
}

variable "aws_region" {
  description = "AWS commercial region for the remote state bucket and KMS key."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^(af|ap|ca|eu|il|me|mx|sa|us)-(central|east|north|northeast|northwest|south|southeast|southwest|west)-[1-9][0-9]*$", var.aws_region))
    error_message = "aws_region must be an AWS commercial-region identifier, for example us-east-1."
  }
}

variable "administrator_role_arns" {
  description = "Existing roles in the current account that explicitly administer the state key. Include the bootstrap operator's role."
  type        = set(string)
  nullable    = false

  validation {
    condition = length(var.administrator_role_arns) > 0 && alltrue([
      for arn in var.administrator_role_arns :
      can(regex("^arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/([A-Za-z0-9_+=,.@-]+/)*[A-Za-z0-9_+=,.@-]+$", arn))
    ])
    error_message = "Supply at least one explicit IAM role ARN from the current AWS account; wildcard, user, and external principals are prohibited."
  }
}

variable "tags" {
  description = "Additional tags for the state bucket and encryption key."
  type        = map(string)
  default     = {}
  nullable    = false
}
