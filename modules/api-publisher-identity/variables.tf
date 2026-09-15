variable "project_name" {
  type        = string
  description = "Nome base do projeto."
  default     = "oficina-mecanica"

  validation {
    condition     = var.project_name == "oficina-mecanica"
    error_message = "project_name deve ser oficina-mecanica."
  }
}

variable "github_organization" {
  type        = string
  description = "Organizacao proprietaria do repositorio da API."

  validation {
    condition     = var.github_organization == "32SOAT"
    error_message = "github_organization deve ser 32SOAT."
  }
}

variable "github_repository" {
  type        = string
  description = "Repositorio autorizado a publicar imagens."

  validation {
    condition     = var.github_repository == "oficina-mecanica-api"
    error_message = "github_repository deve ser oficina-mecanica-api."
  }
}

variable "github_oidc_provider_arn" {
  type        = string
  description = "ARN do provedor GitHub OIDC da conta AWS."

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_oidc_provider_arn))
    error_message = "github_oidc_provider_arn deve apontar para token.actions.githubusercontent.com."
  }
}

variable "github_environment" {
  type        = string
  description = "GitHub Environment exclusivo da publicacao manual."

  validation {
    condition     = var.github_environment == "image-publishing"
    error_message = "github_environment deve ser image-publishing."
  }
}

variable "ecr_repository_arn" {
  type        = string
  description = "ARN do repositorio ECR compartilhado."

  validation {
    condition     = can(regex("^arn:aws:ecr:[a-z0-9-]+:[0-9]{12}:repository/oficina-mecanica-api$", var.ecr_repository_arn))
    error_message = "ecr_repository_arn deve identificar o repositorio oficina-mecanica-api."
  }
}

variable "ecr_repository_url_parameter_arn" {
  type        = string
  description = "ARN do parametro SSM que publica a URL do ECR."

  validation {
    condition     = can(regex("^arn:aws:ssm:[a-z0-9-]+:[0-9]{12}:parameter/oficina/shared/ecr/repository-url$", var.ecr_repository_url_parameter_arn))
    error_message = "ecr_repository_url_parameter_arn deve identificar o contrato compartilhado da URL do ECR."
  }
}

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary bootstrap obrigatoria para a role publisher."

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:policy/oficina-mecanica-shared-api-publisher-boundary$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn deve ser a boundary dedicada do publisher."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags adicionais da role publisher."
  default     = {}
}
