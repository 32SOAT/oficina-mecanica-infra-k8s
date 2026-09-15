locals {
  parameters = {
    "aws-region" = {
      value       = var.aws_region
      description = "Regiao AWS usada pelos consumidores da plataforma."
    }
    "vpc-id" = {
      value       = var.vpc_id
      description = "VPC que hospeda os recursos do ambiente."
    }
    "public-subnet-ids" = {
      value       = jsonencode(var.public_subnet_ids)
      description = "Subnets publicas do ambiente serializadas como JSON."
    }
    "private-subnet-ids" = {
      value       = jsonencode(var.private_subnet_ids)
      description = "Subnets privadas do ambiente serializadas como JSON."
    }
    "database-subnet-ids" = {
      value       = jsonencode(var.database_subnet_ids)
      description = "Subnets do banco gerenciado serializadas como JSON."
    }
    "database-client-security-group-id" = {
      value       = var.database_client_security_group_id
      description = "Security group dos clientes autorizados do banco gerenciado."
    }
    "eks-cluster-name" = {
      value       = var.eks_cluster_name
      description = "Nome do cluster EKS do ambiente."
    }
  }
  tags = merge(var.tags, {
    Owner       = var.owner
    Environment = var.environment
    Source      = "oficina-mecanica-infra-k8s"
    Project     = "oficina-mecanica"
    ManagedBy   = "Terraform"
  })
}

resource "aws_ssm_parameter" "platform" {
  for_each = local.parameters

  name        = "/oficina/${var.environment}/platform/${each.key}"
  description = each.value.description
  type        = "String"
  value       = each.value.value
  tags        = local.tags
}
