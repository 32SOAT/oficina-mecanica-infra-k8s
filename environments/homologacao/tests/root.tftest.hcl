mock_provider "aws" {
  override_during = plan

  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b"] }
  }

  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }

  mock_data "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:us-east-1:123456789012:repository/oficina-mecanica-api"
      name           = "oficina-mecanica-api"
      repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/oficina-mecanica-api"
    }
  }

  mock_data "aws_subnet" {
    defaults = { vpc_id = "vpc-mocked" }
  }
}

override_resource {
  target          = module.eks.aws_eks_cluster.this
  override_during = plan
  values = {
    name = "oficina-mecanica-homologacao"
    certificate_authority = [{
      data = "dGVzdC1jYQ=="
    }]
    identity = [{
      oidc = [{
        issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/HOMOLOGACAO"
      }]
    }]
    vpc_config = {
      cluster_security_group_id = "sg-cluster-homologacao"
      endpoint_private_access   = true
      endpoint_public_access    = true
      public_access_cidrs       = toset(["203.0.113.0/24"])
      security_group_ids        = toset([])
      subnet_ids                = toset(["subnet-a", "subnet-b"])
      vpc_id                    = "vpc-mocked"
    }
  }
}

override_resource {
  target          = module.api_deployer_identity.aws_iam_role.deployer
  override_during = plan
  values = {
    arn = "arn:aws:iam::123456789012:role/oficina-mecanica-homologacao-api-deployer"
  }
}

variables {
  aws_region                           = "us-east-1"
  github_oidc_provider_arn             = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  cluster_permissions_boundary_arn     = "arn:aws:iam::123456789012:policy/oficina-mecanica-homologacao-eks-cluster-boundary"
  node_permissions_boundary_arn        = "arn:aws:iam::123456789012:policy/oficina-mecanica-homologacao-eks-node-boundary"
  deployer_permissions_boundary_arn    = "arn:aws:iam::123456789012:policy/oficina-mecanica-homologacao-api-deployer-boundary"
  vpc_cidr                             = "10.20.0.0/16"
  az_count                             = 2
  single_nat_gateway                   = true
  cluster_version                      = "1.36"
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/24"]
  cluster_enabled_log_types            = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  node_instance_types                  = ["t3.medium"]
  node_capacity_type                   = "SPOT"
  node_min_size                        = 1
  node_desired_size                    = 1
  node_max_size                        = 3
  node_disk_size                       = 30
}

run "homologacao_root_exposes_safe_wrapper_contract" {
  command = plan

  assert {
    condition     = output.cluster_name == "oficina-mecanica-homologacao"
    error_message = "The environment root must expose cluster_name for the guarded output wrapper."
  }

  assert {
    condition     = output.deployer_role_arn == "arn:aws:iam::123456789012:role/oficina-mecanica-homologacao-api-deployer"
    error_message = "The environment root must expose deployer_role_arn for the guarded output wrapper."
  }

  assert {
    condition     = module.eks.cluster_name == "oficina-mecanica-homologacao"
    error_message = "The root must compose network outputs into the deterministic EKS module."
  }
}

run "reject_noncanonical_ipv4_global_route" {
  command = plan
  variables { cluster_endpoint_public_access_cidrs = ["0.0.0.0/00"] }
  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}

run "reject_expanded_ipv6_global_route" {
  command = plan
  variables { cluster_endpoint_public_access_cidrs = ["0:0:0:0:0:0:0:0/0"] }
  expect_failures = [var.cluster_endpoint_public_access_cidrs]
}
