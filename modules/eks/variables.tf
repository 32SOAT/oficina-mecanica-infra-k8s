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

variable "vpc_id" {
  type        = string
  description = "ID da VPC que hospeda o cluster."

  validation {
    condition     = can(regex("^vpc-[a-zA-Z0-9]+$", var.vpc_id))
    error_message = "vpc_id deve ser um ID de VPC nao vazio."
  }
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "IDs das subnets privadas usadas pelo control plane e node group."

  validation {
    condition = (
      length(var.private_subnet_ids) >= 2 &&
      length(distinct(var.private_subnet_ids)) == length(var.private_subnet_ids) &&
      alltrue([for subnet_id in var.private_subnet_ids : can(regex("^subnet-[a-zA-Z0-9-]+$", subnet_id))])
    )
    error_message = "private_subnet_ids deve conter ao menos duas subnets distintas e validas."
  }
}

variable "cluster_version" {
  type        = string
  description = "Versao Kubernetes promovida explicitamente para o EKS."

  validation {
    condition     = var.cluster_version == "1.36"
    error_message = "cluster_version deve permanecer fixado em 1.36 nesta entrega."
  }
}

variable "cluster_endpoint_public_access" {
  type        = bool
  description = "Habilita o endpoint publico do EKS, sempre com CIDRs restritos."
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDRs autorizados a acessar o endpoint publico do EKS."

  validation {
    condition = (
      (!var.cluster_endpoint_public_access || length(var.cluster_endpoint_public_access_cidrs) > 0) &&
      alltrue([
        for cidr in var.cluster_endpoint_public_access_cidrs : try(
          !contains(
            ["0.0.0.0/0", "::/0"],
            "${cidrhost(cidr, 0)}/${tonumber(split("/", cidr)[1])}"
          ),
          false
        )
      ])
    )
    error_message = "Informe CIDRs validos e restritos quando o endpoint publico estiver habilitado."
  }
}

variable "cluster_enabled_log_types" {
  type        = list(string)
  description = "Logs do control plane enviados ao CloudWatch."

  validation {
    condition = (
      length(var.cluster_enabled_log_types) > 0 &&
      length(distinct(var.cluster_enabled_log_types)) == length(var.cluster_enabled_log_types) &&
      alltrue([
        for log_type in var.cluster_enabled_log_types :
        contains(["api", "audit", "authenticator", "controllerManager", "scheduler"], log_type)
      ])
    )
    error_message = "Habilite ao menos um tipo valido de log do control plane, sem duplicatas."
  }
}

variable "cluster_permissions_boundary_arn" {
  type        = string
  description = "ARN da permissions boundary obrigatoria para a role do cluster."

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:policy/[A-Za-z0-9+=,.@_/-]+$", var.cluster_permissions_boundary_arn))
    error_message = "cluster_permissions_boundary_arn deve ser um ARN IAM de policy valido."
  }
}

variable "node_permissions_boundary_arn" {
  type        = string
  description = "ARN da permissions boundary obrigatoria para a role dos nodes."

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:policy/[A-Za-z0-9+=,.@_/-]+$", var.node_permissions_boundary_arn))
    error_message = "node_permissions_boundary_arn deve ser um ARN IAM de policy valido."
  }
}

variable "node_instance_types" {
  type        = list(string)
  description = "Tipos de instancia usados pelo node group."

  validation {
    condition     = length(var.node_instance_types) > 0 && alltrue([for instance_type in var.node_instance_types : trimspace(instance_type) != ""])
    error_message = "node_instance_types deve conter ao menos um tipo de instancia."
  }
}

variable "node_capacity_type" {
  type        = string
  description = "Tipo de capacidade do node group: ON_DEMAND ou SPOT."

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type deve ser ON_DEMAND ou SPOT."
  }
}

variable "node_min_size" {
  type        = number
  description = "Quantidade minima de nodes."

  validation {
    condition     = var.node_min_size >= 0 && floor(var.node_min_size) == var.node_min_size
    error_message = "node_min_size deve ser um inteiro maior ou igual a zero."
  }
}

variable "node_desired_size" {
  type        = number
  description = "Quantidade desejada de nodes."

  validation {
    condition = (
      floor(var.node_desired_size) == var.node_desired_size &&
      var.node_desired_size >= var.node_min_size &&
      var.node_desired_size <= var.node_max_size
    )
    error_message = "node_desired_size deve ser inteiro e permanecer entre node_min_size e node_max_size."
  }
}

variable "node_max_size" {
  type        = number
  description = "Quantidade maxima de nodes."

  validation {
    condition     = var.node_max_size >= 1 && floor(var.node_max_size) == var.node_max_size && var.node_max_size >= var.node_min_size
    error_message = "node_max_size deve ser inteiro, positivo e maior ou igual a node_min_size."
  }
}

variable "node_disk_size" {
  type        = number
  description = "Tamanho do disco dos nodes, em GiB."

  validation {
    condition     = var.node_disk_size >= 20 && floor(var.node_disk_size) == var.node_disk_size
    error_message = "node_disk_size deve ser um inteiro de ao menos 20 GiB."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags adicionais aplicadas aos recursos AWS."
  default     = {}
}
