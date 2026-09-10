variable "repository_name" {
  type        = string
  description = "Nome deterministico do repositorio ECR da API."
  default     = "oficina-mecanica-api"

  validation {
    condition     = trimspace(var.repository_name) != "" && can(regex("^[a-z0-9]+(?:[._/-][a-z0-9]+)*$", var.repository_name))
    error_message = "repository_name deve ser um nome ECR nao vazio e valido."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags adicionais aplicadas ao repositorio."
  default     = {}
}
