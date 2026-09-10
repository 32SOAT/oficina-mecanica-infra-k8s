output "repository_arn" {
  description = "ARN do repositorio compartilhado da API."
  value       = aws_ecr_repository.api.arn
}

output "repository_name" {
  description = "Nome do repositorio compartilhado da API."
  value       = aws_ecr_repository.api.name
}

output "repository_url" {
  description = "URL do repositorio compartilhado da API."
  value       = aws_ecr_repository.api.repository_url
}
