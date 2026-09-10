variable "environment" {
  type        = string
  description = "Ambiente dos parametros publicados."

  validation {
    condition     = contains(["homologacao", "producao"], var.environment)
    error_message = "environment deve ser homologacao ou producao."
  }
}

variable "aws_region" {
  type        = string
  description = "Regiao AWS do ambiente."

  validation {
    condition     = trimspace(var.aws_region) != "" && can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region deve ser uma regiao AWS nao vazia."
  }
}

variable "vpc_id" {
  type        = string
  description = "ID da VPC do ambiente."

  validation {
    condition     = trimspace(var.vpc_id) != ""
    error_message = "vpc_id nao pode ser vazio."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "IDs das subnets publicas."

  validation {
    condition     = length(var.public_subnet_ids) > 0 && alltrue([for value in var.public_subnet_ids : trimspace(value) != ""])
    error_message = "public_subnet_ids deve conter apenas valores nao vazios."
  }
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs das subnets privadas."

  validation {
    condition     = length(var.private_subnet_ids) > 0 && alltrue([for value in var.private_subnet_ids : trimspace(value) != ""])
    error_message = "private_subnet_ids deve conter apenas valores nao vazios."
  }
}

variable "database_subnet_ids" {
  type        = list(string)
  description = "IDs das subnets reservadas para o banco gerenciado."

  validation {
    condition     = length(var.database_subnet_ids) > 0 && alltrue([for value in var.database_subnet_ids : trimspace(value) != ""])
    error_message = "database_subnet_ids deve conter apenas valores nao vazios."
  }
}

variable "database_client_security_group_id" {
  type        = string
  description = "Security group que identifica os clientes autorizados do banco."

  validation {
    condition     = trimspace(var.database_client_security_group_id) != ""
    error_message = "database_client_security_group_id nao pode ser vazio."
  }
}

variable "eks_cluster_name" {
  type        = string
  description = "Nome do cluster EKS do ambiente."

  validation {
    condition     = trimspace(var.eks_cluster_name) != ""
    error_message = "eks_cluster_name nao pode ser vazio."
  }
}

variable "owner" {
  type        = string
  description = "Equipe proprietaria do contrato."
  default     = "platform"

  validation {
    condition     = trimspace(var.owner) != ""
    error_message = "owner nao pode ser vazio."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags adicionais aplicadas aos parametros."
  default     = {}
}
