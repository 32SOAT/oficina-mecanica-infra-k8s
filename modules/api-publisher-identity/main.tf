locals {
  aws_region = split(":", var.ecr_repository_arn)[3]
  role_name  = "${var.project_name}-shared-api-publisher"
  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = "shared"
    ManagedBy   = "Terraform"
    Component   = "api-image-publisher"
  })
}

resource "aws_iam_role" "publisher" {
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

resource "aws_iam_role_policy" "publisher" {
  name = "publish-api-image"
  role = aws_iam_role.publisher.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AuthenticateToRegionalECR"
        Effect    = "Allow"
        Action    = ["ecr:GetAuthorizationToken"]
        Resource  = ["*"]
        Condition = { StringEquals = { "aws:RequestedRegion" = local.aws_region } }
      },
      {
        Sid      = "ReadRepositoryContract"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = [var.ecr_repository_url_parameter_arn]
      },
      {
        Sid    = "UploadImmutableImage"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = [var.ecr_repository_arn]
      },
    ]
  })
}
