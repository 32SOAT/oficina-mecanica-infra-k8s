variable "repository_name" {
  type        = string
  description = "Nome deterministico do repositorio ECR da API."
  default     = "oficina-mecanica-api"

  validation {
    condition     = var.repository_name == "oficina-mecanica-api"
    error_message = "repository_name deve ser oficina-mecanica-api."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags adicionais aplicadas ao repositorio."
  default     = {}
}
