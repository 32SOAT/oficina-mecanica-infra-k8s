data "aws_subnet" "private" {
  count = length(var.private_subnet_ids)
  id    = var.private_subnet_ids[count.index]
}

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.name_prefix}/cluster"
  retention_in_days = 30
  tags              = local.common_tags
}

# EKS 1.36 encrypts Kubernetes API data with envelope encryption by default.
# A customer-managed KMS key remains configurable through encryption_config,
# but it is not required by this module's current contract.
#trivy:ignore:AWS-0039
resource "aws_eks_cluster" "this" {
  name                      = local.name_prefix
  role_arn                  = aws_iam_role.eks_cluster.arn
  version                   = var.cluster_version
  enabled_cluster_log_types = var.cluster_enabled_log_types

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  lifecycle {
    precondition {
      condition     = alltrue([for subnet in data.aws_subnet.private : subnet.vpc_id == var.vpc_id])
      error_message = "Todas as private_subnet_ids devem pertencer a vpc_id."
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_cloudwatch_log_group.eks,
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

resource "aws_eks_node_group" "api" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.name_prefix}-api"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.private_subnet_ids
  capacity_type   = var.node_capacity_type
  disk_size       = var.node_disk_size
  instance_types  = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    workload = "api"
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_readonly
  ]
}
