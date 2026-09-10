variable "aws_region" {
  type        = string
  description = "Regiao AWS do ambiente."

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

variable "cluster_permissions_boundary_arn" {
  type        = string
  description = "ARN da permissions boundary dedicada a role do cluster EKS de producao."

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:policy/oficina-mecanica-producao-eks-cluster-boundary$", var.cluster_permissions_boundary_arn))
    error_message = "cluster_permissions_boundary_arn deve ser a boundary do cluster de producao."
  }
}

variable "node_permissions_boundary_arn" {
  type        = string
  description = "ARN da permissions boundary dedicada a role dos nodes EKS de producao."

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:policy/oficina-mecanica-producao-eks-node-boundary$", var.node_permissions_boundary_arn))
    error_message = "node_permissions_boundary_arn deve ser a boundary dos nodes de producao."
  }
}

variable "deployer_permissions_boundary_arn" {
  type        = string
  description = "ARN da permissions boundary dedicada a role de deploy de producao."

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:policy/oficina-mecanica-producao-api-deployer-boundary$", var.deployer_permissions_boundary_arn))
    error_message = "deployer_permissions_boundary_arn deve ser a boundary do deployer de producao."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR principal da VPC de producao."
}

variable "az_count" {
  type        = number
  description = "Quantidade de zonas de disponibilidade usadas."

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3 && floor(var.az_count) == var.az_count
    error_message = "az_count deve ser 2 ou 3."
  }
}

variable "single_nat_gateway" {
  type        = bool
  description = "Quando false, cria um NAT Gateway por zona."
}

variable "cluster_version" {
  type        = string
  description = "Versao Kubernetes promovida explicitamente."

  validation {
    condition     = var.cluster_version == "1.36"
    error_message = "cluster_version deve permanecer fixado em 1.36."
  }
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs restritos autorizados no endpoint publico do EKS; fornecidos fora do repositorio."

  validation {
    condition = (
      length(var.cluster_endpoint_public_access_cidrs) > 0 &&
      !contains(var.cluster_endpoint_public_access_cidrs, "0.0.0.0/0") &&
      !contains(var.cluster_endpoint_public_access_cidrs, "::/0") &&
      alltrue([for cidr in var.cluster_endpoint_public_access_cidrs : can(cidrhost(cidr, 0))])
    )
    error_message = "Informe ao menos um CIDR valido e restrito para o endpoint publico."
  }
}

variable "cluster_enabled_log_types" {
  type        = list(string)
  description = "Logs do control plane enviados ao CloudWatch."
}

variable "node_instance_types" {
  type        = list(string)
  description = "Tipos de instancia usados pelo node group."
}

variable "node_capacity_type" {
  type        = string
  description = "Tipo de capacidade do node group."
}

variable "node_min_size" {
  type        = number
  description = "Quantidade minima de nodes."
}

variable "node_desired_size" {
  type        = number
  description = "Quantidade desejada de nodes."
}

variable "node_max_size" {
  type        = number
  description = "Quantidade maxima de nodes."
}

variable "node_disk_size" {
  type        = number
  description = "Tamanho do disco dos nodes, em GiB."
}

variable "tags" {
  type        = map(string)
  description = "Tags adicionais dos recursos de producao."
  default     = {}
}
