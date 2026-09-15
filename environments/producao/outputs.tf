output "aws_region" {
  description = "Regiao AWS do ambiente."
  value       = var.aws_region
}

output "vpc_id" {
  description = "ID da VPC de producao."
  value       = module.network.vpc_id
}

output "public_subnet_ids" {
  description = "IDs das subnets publicas de producao."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas de producao."
  value       = module.network.private_subnet_ids
}

output "database_subnet_ids" {
  description = "IDs das subnets reservadas para o banco gerenciado."
  value       = module.network.database_subnet_ids
}

output "cluster_name" {
  description = "Nome do cluster EKS de producao."
  value       = module.eks.cluster_name
}

output "database_client_security_group_id" {
  description = "Security group usado para autorizar clientes do banco."
  value       = module.eks.database_client_security_group_id
}

output "deployer_role_arn" {
  description = "ARN da role OIDC de deploy em producao."
  value       = module.api_deployer_identity.deployer_role_arn
}

output "platform_contract_parameter_names" {
  description = "Nomes dos parametros SSM publicados para consumidores."
  value       = module.platform_contract.parameter_names
}

output "ecr_repository_url" {
  description = "URL do ECR compartilhado consultado por nome deterministico."
  value       = data.aws_ecr_repository.api.repository_url
}

output "api_gateway_id" {
  description = "ID do API Gateway HTTP de producao."
  value       = module.api_gateway_http.api_id
}

output "api_gateway_endpoint" {
  description = "Endpoint padrao execute-api de producao."
  value       = module.api_gateway_http.api_endpoint
}

output "api_gateway_lambda_integration_id" {
  description = "ID da integracao da rota de autenticacao."
  value       = module.api_gateway_http.lambda_integration_id
}

output "api_gateway_nlb_integration_id" {
  description = "ID da integracao proxy com o NLB."
  value       = module.api_gateway_http.nlb_integration_id
}
