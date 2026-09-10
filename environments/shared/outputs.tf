output "ecr_repository_name" {
  description = "Nome deterministico do repositorio ECR compartilhado."
  value       = module.ecr.repository_name
}

output "repository_url" {
  description = "URL nao sensivel do repositorio ECR compartilhado."
  value       = module.ecr.repository_url
}

output "ecr_repository_url_parameter_name" {
  description = "Nome do contrato SSM usado pelo pipeline da API."
  value       = aws_ssm_parameter.ecr_repository_url.name
}

output "publisher_role_arn" {
  description = "ARN da role OIDC usada exclusivamente na publicacao manual de imagens."
  value       = module.api_publisher_identity.publisher_role_arn
}
