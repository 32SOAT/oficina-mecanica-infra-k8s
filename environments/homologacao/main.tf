data "aws_caller_identity" "current" {}

data "aws_ecr_repository" "api" {
  name = "oficina-mecanica-api"
}

data "aws_ssm_parameter" "auth_lambda_arn" {
  name            = "/oficina/homologacao/platform/auth-lambda-arn"
  with_decryption = false
}

data "aws_ssm_parameter" "api_nlb_hostname" {
  name            = "/oficina/homologacao/platform/api-nlb-hostname"
  with_decryption = false
}

locals {
  environment  = "homologacao"
  project_name = "oficina-mecanica"
  cluster_arn  = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${module.eks.cluster_name}"
}

module "network" {
  source = "../../modules/network"

  project_name       = local.project_name
  environment        = local.environment
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
  tags               = var.tags
}

# O endpoint publico e necessario ao runner GitHub hospedado e aceita somente
# CIDRs explicitos, validados contra rotas globais neste root e no modulo.
#trivy:ignore:AWS-0040
module "eks" {
  source = "../../modules/eks"

  project_name                         = local.project_name
  environment                          = local.environment
  vpc_id                               = module.network.vpc_id
  private_subnet_ids                   = module.network.private_subnet_ids
  cluster_version                      = var.cluster_version
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  cluster_enabled_log_types            = var.cluster_enabled_log_types
  cluster_permissions_boundary_arn     = var.cluster_permissions_boundary_arn
  node_permissions_boundary_arn        = var.node_permissions_boundary_arn
  node_instance_types                  = var.node_instance_types
  node_capacity_type                   = var.node_capacity_type
  node_min_size                        = var.node_min_size
  node_desired_size                    = var.node_desired_size
  node_max_size                        = var.node_max_size
  node_disk_size                       = var.node_disk_size
  tags                                 = var.tags

  depends_on = [module.network]
}

module "api_deployer_identity" {
  source = "../../modules/api-deployer-identity"

  environment              = local.environment
  github_organization      = "32SOAT"
  github_organization_id   = "269042072"
  github_repository        = "oficina-mecanica-infra-k8s"
  github_repository_id     = "1315441444"
  github_oidc_provider_arn = var.github_oidc_provider_arn
  github_environment       = local.environment
  cluster_name             = module.eks.cluster_name
  cluster_arn              = local.cluster_arn
  ecr_repository_arn       = data.aws_ecr_repository.api.arn
  permissions_boundary_arn = var.deployer_permissions_boundary_arn
  tags                     = var.tags
}

module "platform_contract" {
  source = "../../modules/platform-contract"

  environment                       = local.environment
  aws_region                        = var.aws_region
  vpc_id                            = module.network.vpc_id
  public_subnet_ids                 = module.network.public_subnet_ids
  private_subnet_ids                = module.network.private_subnet_ids
  database_subnet_ids               = module.network.database_subnet_ids
  database_client_security_group_id = module.eks.database_client_security_group_id
  eks_cluster_name                  = module.eks.cluster_name
  tags                              = var.tags
}

module "api_gateway_http" {
  source = "../../modules/api-gateway-http"

  environment  = local.environment
  api_name     = "${local.project_name}-${local.environment}-http"
  lambda_arn   = data.aws_ssm_parameter.auth_lambda_arn.value
  nlb_hostname = data.aws_ssm_parameter.api_nlb_hostname.value
  aws_region   = var.aws_region
  tags         = var.tags
}
