module "ecr" {
  source = "../../modules/ecr"

  repository_name = "oficina-mecanica-api"
  tags = merge(var.tags, {
    Component = "container-registry"
  })
}

resource "aws_ssm_parameter" "ecr_repository_url" {
  name        = "/oficina/shared/ecr/repository-url"
  description = "URL do repositorio ECR compartilhado da API."
  type        = "String"
  value       = module.ecr.repository_url

  tags = merge(var.tags, {
    Component = "platform-contract"
    Owner     = "platform"
  })
}

module "api_publisher_identity" {
  source = "../../modules/api-publisher-identity"

  github_organization              = "32SOAT"
  github_repository                = "oficina-mecanica-api"
  github_oidc_provider_arn         = var.github_oidc_provider_arn
  github_environment               = "image-publishing"
  ecr_repository_arn               = module.ecr.repository_arn
  ecr_repository_url_parameter_arn = aws_ssm_parameter.ecr_repository_url.arn
  permissions_boundary_arn         = var.publisher_permissions_boundary_arn
  tags = merge(var.tags, {
    Component = "api-image-publisher"
  })
}
