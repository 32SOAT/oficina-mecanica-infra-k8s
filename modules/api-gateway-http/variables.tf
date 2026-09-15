variable "environment" {
  type        = string
  description = "Ambiente dono do API Gateway."

  validation {
    condition     = contains(["homologacao", "producao"], var.environment)
    error_message = "environment deve ser homologacao ou producao."
  }
}

variable "api_name" {
  type        = string
  description = "Nome do API Gateway."

  validation {
    condition     = trimspace(var.api_name) != ""
    error_message = "api_name nao pode ser vazio."
  }
}

variable "lambda_arn" {
  type        = string
  description = "ARN da Lambda de autenticacao consumido do contrato SSM."

  validation {
    condition     = can(regex("^arn:aws:lambda:[a-z]{2}-[a-z]+-[0-9]:[0-9]{12}:function:[A-Za-z0-9-_]+$", var.lambda_arn))
    error_message = "lambda_arn deve ser um ARN de funcao Lambda valido."
  }
}

variable "nlb_hostname" {
  type        = string
  description = "Hostname publico do NLB da API NestJS consumido do contrato SSM."

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$", var.nlb_hostname))
    error_message = "nlb_hostname deve ser um hostname sem protocolo ou barra."
  }
}

variable "aws_region" {
  type        = string
  description = "Regiao AWS do API Gateway."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region deve ser uma regiao AWS valida."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags adicionais."
  default     = {}
}
