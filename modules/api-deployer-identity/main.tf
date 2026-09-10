locals {
  cluster_arn_parts = split(":", var.cluster_arn)
  aws_region        = local.cluster_arn_parts[3]
  aws_account_id    = local.cluster_arn_parts[4]
  role_name         = "${var.project_name}-${var.environment}-api-deployer"
  parameter_names = [
    "aws-region",
    "vpc-id",
    "public-subnet-ids",
    "private-subnet-ids",
    "database-subnet-ids",
    "database-client-security-group-id",
    "eks-cluster-name",
  ]
  parameter_arns = concat(
    [for name in local.parameter_names :
      "arn:aws:ssm:${local.aws_region}:${local.aws_account_id}:parameter/oficina/${var.environment}/platform/${name}"
    ],
    ["arn:aws:ssm:${local.aws_region}:${local.aws_account_id}:parameter/oficina/shared/ecr/repository-url"]
  )
  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Component   = "api-deployer"
  })
}

resource "aws_iam_role" "deployer" {
  name                 = local.role_name
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = var.github_oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_organization}/${var.github_repository}:environment:${var.github_environment}"
        }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "deployer" {
  name = "deploy-api-workload"
  role = aws_iam_role.deployer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DiscoverOwnCluster"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = [var.cluster_arn]
      },
      {
        Sid      = "ReadEnvironmentContract"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = local.parameter_arns
      },
      {
        Sid      = "ValidateImageDigest"
        Effect   = "Allow"
        Action   = ["ecr:DescribeImages"]
        Resource = [var.ecr_repository_arn]
      },
    ]
  })
}

resource "aws_eks_access_entry" "deployer" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.deployer.arn
  type          = "STANDARD"
  tags          = local.tags
}

resource "aws_eks_access_policy_association" "deployer" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.deployer.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [var.namespace]
  }

  depends_on = [aws_eks_access_entry.deployer]
}
