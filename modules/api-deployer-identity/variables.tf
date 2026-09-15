variable "project_name" {
  type        = string
  description = "Nome base do projeto."
  default     = "oficina-mecanica"

  validation {
    condition     = var.project_name == "oficina-mecanica"
    error_message = "project_name deve ser oficina-mecanica."
  }
}

variable "environment" {
  type        = string
  description = "Ambiente de deploy da API."

  validation {
    condition     = contains(["homologacao", "producao"], var.environment)
    error_message = "environment deve ser homologacao ou producao."
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
  description = "Repositorio de infraestrutura autorizado a executar deploy."

  validation {
    condition     = var.github_repository == "oficina-mecanica-infra-k8s"
    error_message = "github_repository deve ser oficina-mecanica-infra-k8s."
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
  description = "GitHub Environment que protege o deploy."

  validation {
    condition     = var.github_environment == var.environment
    error_message = "github_environment deve corresponder exatamente a environment."
  }
}

variable "cluster_name" {
  type        = string
  description = "Nome do cluster EKS do ambiente."

  validation {
    condition     = var.cluster_name == "${var.project_name}-${var.environment}"
    error_message = "cluster_name deve seguir project_name-environment."
  }
}

variable "cluster_arn" {
  type        = string
  description = "ARN do cluster EKS do ambiente."

  validation {
    condition     = can(regex("^arn:aws:eks:[a-z0-9-]+:[0-9]{12}:cluster/oficina-mecanica-(homologacao|producao)$", var.cluster_arn))
    error_message = "cluster_arn deve identificar um cluster oficina-mecanica de ambiente valido."
  }
}

variable "namespace" {
  type        = string
  description = "Namespace Kubernetes exclusivo da API."
  default     = "oficina-mecanica"

  validation {
    condition     = var.namespace == "oficina-mecanica"
    error_message = "namespace deve ser oficina-mecanica."
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

variable "permissions_boundary_arn" {
  type        = string
  description = "Boundary bootstrap obrigatoria para a role deployer."

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:policy/oficina-mecanica-(homologacao|producao)-api-deployer-boundary$", var.permissions_boundary_arn)) && endswith(var.permissions_boundary_arn, "-${var.environment}-api-deployer-boundary")
    error_message = "permissions_boundary_arn deve ser a boundary dedicada do deployer deste ambiente."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags adicionais da role e do access entry."
  default     = {}
}
