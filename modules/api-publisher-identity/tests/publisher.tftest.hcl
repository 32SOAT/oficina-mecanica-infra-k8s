mock_provider "aws" {
  override_during = plan
}

override_resource {
  target          = aws_iam_role.publisher
  override_during = plan
  values = {
    id   = "oficina-mecanica-shared-api-publisher"
    name = "oficina-mecanica-shared-api-publisher"
    arn  = "arn:aws:iam::123456789012:role/oficina-mecanica-shared-api-publisher"
  }
}

variables {
  project_name                     = "oficina-mecanica"
  github_organization              = "32SOAT"
  github_repository                = "oficina-mecanica-api"
  github_oidc_provider_arn         = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  github_environment               = "image-publishing"
  ecr_repository_arn               = "arn:aws:ecr:us-east-1:123456789012:repository/oficina-mecanica-api"
  ecr_repository_url_parameter_arn = "arn:aws:ssm:us-east-1:123456789012:parameter/oficina/shared/ecr/repository-url"
  permissions_boundary_arn         = "arn:aws:iam::123456789012:policy/oficina-mecanica-shared-api-publisher-boundary"
}

run "publisher_trust_and_permissions_are_exact" {
  command = plan

  assert {
    condition = (
      aws_iam_role.publisher.name == "oficina-mecanica-shared-api-publisher" &&
      aws_iam_role.publisher.permissions_boundary == var.permissions_boundary_arn &&
      length(jsondecode(aws_iam_role.publisher.assume_role_policy).Statement) == 1 &&
      one(jsondecode(aws_iam_role.publisher.assume_role_policy).Statement).Principal == { Federated = var.github_oidc_provider_arn } &&
      one(jsondecode(aws_iam_role.publisher.assume_role_policy).Statement).Action == "sts:AssumeRoleWithWebIdentity" &&
      one(jsondecode(aws_iam_role.publisher.assume_role_policy).Statement).Condition.StringEquals == {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "repo:32SOAT/oficina-mecanica-api:environment:image-publishing"
      } &&
      !strcontains(aws_iam_role.publisher.assume_role_policy, "*")
    )
    error_message = "Publisher must use its exact API/environment OIDC trust and its bootstrap its bootstrap boundary."
  }

  assert {
    condition = (
      length([for statement in jsondecode(aws_iam_role_policy.publisher.policy).Statement : statement if
        toset(statement.Action) == toset(["ecr:GetAuthorizationToken"]) &&
        statement.Resource == ["*"] &&
        statement.Condition.StringEquals["aws:RequestedRegion"] == "us-east-1"
      ]) == 1 &&
      length([for statement in jsondecode(aws_iam_role_policy.publisher.policy).Statement : statement if
        toset(statement.Action) == toset(["ssm:GetParameter"]) &&
        statement.Resource == [var.ecr_repository_url_parameter_arn]
      ]) == 1 &&
      length([for statement in jsondecode(aws_iam_role_policy.publisher.policy).Statement : statement if
        toset(statement.Action) == toset([
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]) && statement.Resource == [var.ecr_repository_arn]
      ]) == 1
    )
    error_message = "Publisher must receive only global regional auth, one contract read, and upload on the exact repository."
  }

  assert {
    condition = alltrue(flatten([for statement in jsondecode(aws_iam_role_policy.publisher.policy).Statement : [for action in statement.Action :
      !contains([
        "ecr:BatchDeleteImage", "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:DeleteRepositoryPolicy",
        "ecr:PutLifecyclePolicy", "ecr:SetRepositoryPolicy", "eks:DescribeCluster", "eks:UpdateClusterConfig",
        "rds:DescribeDBInstances", "s3:GetObject", "s3:PutObject",
      ], action) && !startswith(action, "eks:") && !startswith(action, "rds:") && !startswith(action, "s3:")
    ]]))
    error_message = "Publisher must not delete/manage ECR or access EKS, RDS, or Terraform state."
  }

  assert {
    condition     = output.publisher_role_arn == aws_iam_role.publisher.arn
    error_message = "Publisher output must expose the managed role ARN."
  }
}

run "reject_non_publishing_environment" {
  command = plan
  variables { github_environment = "homologacao" }
  expect_failures = [var.github_environment]
}

run "reject_wrong_publisher_boundary" {
  command = plan
  variables { permissions_boundary_arn = "arn:aws:iam::123456789012:policy/oficina-mecanica-shared-runtime-boundary" }
  expect_failures = [var.permissions_boundary_arn]
}
