variable "project_name" {
  type        = string
  description = "Nome base usado em tags e nomes de recursos."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Use apenas letras minusculas, numeros e hifens em project_name."
  }
}

variable "environment" {
  type        = string
  description = "Ambiente da infraestrutura."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "Use apenas letras minusculas, numeros e hifens em environment."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR principal da VPC."

  validation {
    condition     = can(cidrsubnet(var.vpc_cidr, 4, 8))
    error_message = "vpc_cidr deve permitir ao menos nove subnets derivadas com quatro bits adicionais."
  }
}

variable "az_count" {
  type        = number
  description = "Quantidade de zonas de disponibilidade usadas para subnets."

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3 && floor(var.az_count) == var.az_count
    error_message = "az_count deve ser 2 ou 3."
  }
}

variable "single_nat_gateway" {
  type        = bool
  description = "Quando true, cria um unico NAT Gateway compartilhado pelas subnets privadas."
}

variable "tags" {
  type        = map(string)
  description = "Tags adicionais aplicadas aos recursos AWS."
  default     = {}
}
