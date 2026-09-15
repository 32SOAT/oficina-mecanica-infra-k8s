variable "aws_region" {
  type        = string
  description = "Regiao AWS dos recursos compartilhados."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region deve ser uma regiao AWS valida."
  }
}

variable "github_oidc_provider_arn" {
  type        = string
  description = "ARN do provedor GitHub OIDC criado pelo bootstrap de identidade."

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_oidc_provider_arn))
    error_message = "github_oidc_provider_arn deve apontar para token.actions.githubusercontent.com."
  }
}

variable "publisher_permissions_boundary_arn" {
  type        = string
  description = "ARN da permissions boundary dedicada a role publisher."

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:policy/oficina-mecanica-shared-api-publisher-boundary$", var.publisher_permissions_boundary_arn))
    error_message = "publisher_permissions_boundary_arn deve ser a boundary dedicada do publisher."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags adicionais dos recursos compartilhados."
  default     = {}
}
