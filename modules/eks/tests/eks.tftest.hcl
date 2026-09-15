# Each assertion catches an EKS isolation, identity, runtime, or integration-contract regression.
# AWS calls are mocked; Terraform evaluates the real resource graph and expressions.
mock_provider "aws" {
  override_during = plan

  mock_data "aws_subnet" {
    defaults = {
      vpc_id = "vpc-0123456789abcdef0"
    }
  }

}

variables {
  project_name                         = "oficina-mecanica"
  environment                          = "homologacao"
  vpc_id                               = "vpc-0123456789abcdef0"
  private_subnet_ids                   = ["subnet-private-a", "subnet-private-b"]
  cluster_version                      = "1.36"
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/24"]
  cluster_enabled_log_types            = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_permissions_boundary_arn     = "arn:aws:iam::123456789012:policy/oficina-mecanica-homologacao-eks-cluster-boundary"
  node_permissions_boundary_arn        = "arn:aws:iam::123456789012:policy/oficina-mecanica-homologacao-eks-node-boundary"
  node_instance_types                  = ["t3.medium"]
  node_capacity_type                   = "SPOT"
  node_min_size                        = 1
  node_desired_size                    = 2
  node_max_size                        = 3
  node_disk_size                       = 30
  tags                                 = { CostCenter = "platform" }
}

run "eks_is_private_observable_and_boundary_limited" {
  command = plan

  assert {
    condition = (
      aws_eks_cluster.this.name == "oficina-mecanica-homologacao" &&
      aws_eks_cluster.this.version == "1.36" &&
      one(aws_eks_cluster.this.access_config).authentication_mode == "API_AND_CONFIG_MAP"
    )
    error_message = "EKS must preserve its deterministic name, pinned version, and migration authentication mode."
  }

  assert {
    condition = (
      one(aws_eks_cluster.this.vpc_config).subnet_ids == toset(["subnet-private-a", "subnet-private-b"]) &&
      one(aws_eks_cluster.this.vpc_config).endpoint_private_access &&
      one(aws_eks_cluster.this.vpc_config).endpoint_public_access &&
      one(aws_eks_cluster.this.vpc_config).public_access_cidrs == toset(["203.0.113.0/24"])
    )
    error_message = "EKS must use only private subnets, always expose a private endpoint, and restrict public access."
  }

  assert {
    condition = (
      toset(aws_eks_cluster.this.enabled_cluster_log_types) == toset(["api", "audit", "authenticator", "controllerManager", "scheduler"]) &&
      aws_cloudwatch_log_group.eks.name == "/aws/eks/oficina-mecanica-homologacao/cluster" &&
      aws_cloudwatch_log_group.eks.retention_in_days == 30
    )
    error_message = "Every control-plane log type must be enabled with explicit CloudWatch retention."
  }

  assert {
    condition = (
      aws_iam_role.eks_cluster.name == "oficina-mecanica-homologacao-eks-cluster" &&
      aws_iam_role.eks_cluster.permissions_boundary == var.cluster_permissions_boundary_arn &&
      jsondecode(aws_iam_role.eks_cluster.assume_role_policy).Statement[0].Principal.Service == "eks.amazonaws.com" &&
      aws_iam_role.eks_node.name == "oficina-mecanica-homologacao-eks-node" &&
      aws_iam_role.eks_node.permissions_boundary == var.node_permissions_boundary_arn &&
      jsondecode(aws_iam_role.eks_node.assume_role_policy).Statement[0].Principal.Service == "ec2.amazonaws.com"
    )
    error_message = "Deterministic EKS roles must attach their stack-specific permissions boundaries and trust only their AWS service."
  }

  assert {
    condition = (
      toset([for attachment in aws_iam_role_policy_attachment.eks_cluster_policy : attachment.policy_arn]) ==
      toset(["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"]) &&
      toset([
        aws_iam_role_policy_attachment.eks_worker_node_policy.policy_arn,
        aws_iam_role_policy_attachment.eks_cni_policy.policy_arn,
        aws_iam_role_policy_attachment.eks_ecr_readonly.policy_arn
        ]) == toset([
        "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
        "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
        "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      ])
    )
    error_message = "Cluster and node roles must retain the managed policies required by the EKS runtime."
  }

  assert {
    condition = (
      aws_eks_node_group.api.node_group_name == "oficina-mecanica-homologacao-api" &&
      toset(aws_eks_node_group.api.subnet_ids) == toset(["subnet-private-a", "subnet-private-b"]) &&
      aws_eks_node_group.api.capacity_type == "SPOT" &&
      toset(aws_eks_node_group.api.instance_types) == toset(["t3.medium"]) &&
      aws_eks_node_group.api.disk_size == 30
    )
    error_message = "The managed node group must run only in private subnets with the requested capacity."
  }

  assert {
    condition = (
      one(aws_eks_node_group.api.scaling_config).min_size == 1 &&
      one(aws_eks_node_group.api.scaling_config).desired_size == 2 &&
      one(aws_eks_node_group.api.scaling_config).max_size == 3
    )
    error_message = "The managed node group must preserve coherent minimum, desired, and maximum sizing."
  }

  assert {
    condition = toset([
      for addon in aws_eks_addon.this : addon.addon_name
    ]) == toset(["vpc-cni", "coredns", "kube-proxy", "eks-pod-identity-agent"])
    error_message = "EKS must install all four required managed add-ons."
  }

  assert {
    condition = alltrue([
      for tags in [
        aws_cloudwatch_log_group.eks.tags,
        aws_iam_role.eks_cluster.tags,
        aws_iam_role.eks_node.tags,
        aws_eks_cluster.this.tags,
        aws_eks_node_group.api.tags
      ] :
      tags["Project"] == "oficina-mecanica" &&
      tags["Environment"] == "homologacao" &&
      tags["ManagedBy"] == "terraform" &&
      tags["CostCenter"] == "platform"
    ])
    error_message = "All taggable EKS resources must carry mandatory ownership tags and caller tags."
  }

}

run "exports_primary_cluster_security_group_for_database_clients" {
  command = plan

  override_resource {
    target          = aws_eks_cluster.this
    override_during = plan
    values = {
      certificate_authority = [{
        data = "dGVzdC1jYQ=="
      }]
      identity = [{
        oidc = [{
          issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE"
        }]
      }]
      vpc_config = {
        cluster_security_group_id = "sg-primary-cluster"
        endpoint_private_access   = true
        endpoint_public_access    = true
        public_access_cidrs       = toset(["203.0.113.0/24"])
        security_group_ids        = toset([])
        subnet_ids                = toset(["subnet-private-a", "subnet-private-b"])
        vpc_id                    = "vpc-0123456789abcdef0"
      }
    }
  }

  assert {
    condition = (
      output.cluster_name == "oficina-mecanica-homologacao" &&
      output.cluster_security_group_id == "sg-primary-cluster" &&
      output.database_client_security_group_id == "sg-primary-cluster"
    )
    error_message = "Database clients must consume the EKS primary cluster security group, not an unattached replacement."
  }
}

run "reject_open_public_endpoint" {
  command = plan
  variables { cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"] }
  expect_failures = [var.cluster_endpoint_public_access_cidrs]
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

run "reject_unpinned_cluster_version" {
  command = plan
  variables { cluster_version = "1.35" }
  expect_failures = [var.cluster_version]
}

run "reject_desired_nodes_below_minimum" {
  command = plan
  variables { node_desired_size = 0 }
  expect_failures = [var.node_desired_size]
}

run "reject_desired_nodes_above_maximum" {
  command = plan
  variables { node_desired_size = 4 }
  expect_failures = [var.node_desired_size]
}
