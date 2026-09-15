terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "network" {
  source = "../../../../network"

  project_name       = "oficina-mecanica"
  environment        = "homologacao"
  vpc_cidr           = "10.20.0.0/16"
  az_count           = 2
  single_nat_gateway = true
}

module "eks" {
  source = "../../.."

  project_name                         = "oficina-mecanica"
  environment                          = "homologacao"
  vpc_id                               = module.network.vpc_id
  private_subnet_ids                   = module.network.private_subnet_ids
  cluster_version                      = "1.36"
  cluster_endpoint_public_access       = false
  cluster_endpoint_public_access_cidrs = []
  cluster_enabled_log_types            = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_permissions_boundary_arn     = "arn:aws:iam::123456789012:policy/oficina-mecanica-homologacao-eks-cluster-boundary"
  node_permissions_boundary_arn        = "arn:aws:iam::123456789012:policy/oficina-mecanica-homologacao-eks-node-boundary"
  node_instance_types                  = ["t3.medium"]
  node_capacity_type                   = "SPOT"
  node_min_size                        = 1
  node_desired_size                    = 2
  node_max_size                        = 3
  node_disk_size                       = 30
}

output "cluster_name" {
  value = module.eks.cluster_name
}
