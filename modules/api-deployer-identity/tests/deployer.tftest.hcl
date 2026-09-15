mock_provider "aws" {
  override_during = plan
}

override_resource {
  target          = aws_iam_role.deployer
  override_during = plan
  values = {
    id   = "oficina-mecanica-homologacao-api-deployer"
    name = "oficina-mecanica-homologacao-api-deployer"
    arn  = "arn:aws:iam::123456789012:role/oficina-mecanica-homologacao-api-deployer"
  }
}

variables {
  project_name             = "oficina-mecanica"
  environment              = "homologacao"
  github_organization      = "32SOAT"
  github_organization_id   = "269042072"
  github_repository        = "oficina-mecanica-infra-k8s"
  github_repository_id     = "1315441444"
  github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  github_environment       = "homologacao"
  cluster_name             = "oficina-mecanica-homologacao"
  cluster_arn              = "arn:aws:eks:us-east-1:123456789012:cluster/oficina-mecanica-homologacao"
  namespace                = "oficina-mecanica"
  ecr_repository_arn       = "arn:aws:ecr:us-east-1:123456789012:repository/oficina-mecanica-api"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/oficina-mecanica-homologacao-api-deployer-boundary"
}

run "deployer_is_limited_to_environment_metadata_and_namespace" {
  command = plan

  assert {
    condition = (
      aws_iam_role.deployer.name == "oficina-mecanica-homologacao-api-deployer" &&
      aws_iam_role.deployer.permissions_boundary == var.permissions_boundary_arn &&
      one(jsondecode(aws_iam_role.deployer.assume_role_policy).Statement).Principal == { Federated = var.github_oidc_provider_arn } &&
      one(jsondecode(aws_iam_role.deployer.assume_role_policy).Statement).Condition.StringEquals == {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "repo:32SOAT@269042072/oficina-mecanica-infra-k8s@1315441444:environment:homologacao"
      } &&
      !strcontains(aws_iam_role.deployer.assume_role_policy, "*")
    )
    error_message = "Deployer must use exact API/environment OIDC trust and its environment boundary."
  }

  assert {
    condition = length([for statement in jsondecode(aws_iam_role_policy.deployer.policy).Statement : statement if
      statement.Action == ["ssm:PutParameter"] && statement.Resource == ["arn:aws:ssm:us-east-1:123456789012:parameter/oficina/homologacao/platform/api-nlb-hostname"]
    ]) == 1
    error_message = "Deployer may publish only its own environment NLB hostname contract."
  }

  assert {
    condition = (
      length([for statement in jsondecode(aws_iam_role_policy.deployer.policy).Statement : statement if
        statement.Action == ["eks:DescribeCluster"] && statement.Resource == [var.cluster_arn]
      ]) == 1 &&
      length([for statement in jsondecode(aws_iam_role_policy.deployer.policy).Statement : statement if
        statement.Action == ["ecr:DescribeImages"] && statement.Resource == [var.ecr_repository_arn]
      ]) == 1 &&
      toset(one([for statement in jsondecode(aws_iam_role_policy.deployer.policy).Statement : statement.Resource if
        toset(statement.Action) == toset(["ssm:GetParameter", "ssm:GetParameters"])
        ])) == toset([
        "arn:aws:ssm:us-east-1:123456789012:parameter/oficina/homologacao/platform/aws-region",
        "arn:aws:ssm:us-east-1:123456789012:parameter/oficina/homologacao/platform/vpc-id",
        "arn:aws:ssm:us-east-1:123456789012:parameter/oficina/homologacao/platform/public-subnet-ids",
        "arn:aws:ssm:us-east-1:123456789012:parameter/oficina/homologacao/platform/private-subnet-ids",
        "arn:aws:ssm:us-east-1:123456789012:parameter/oficina/homologacao/platform/database-subnet-ids",
        "arn:aws:ssm:us-east-1:123456789012:parameter/oficina/homologacao/platform/database-client-security-group-id",
        "arn:aws:ssm:us-east-1:123456789012:parameter/oficina/homologacao/platform/eks-cluster-name",
        "arn:aws:ssm:us-east-1:123456789012:parameter/oficina/shared/ecr/repository-url",
      ])
    )
    error_message = "Deployer permissions must read only its cluster, seven environment parameters, the shared ECR URL, and image metadata."
  }

  assert {
    condition = alltrue(flatten([for statement in jsondecode(aws_iam_role_policy.deployer.policy).Statement : [for action in statement.Action :
      !contains([
        "ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:GetAuthorizationToken",
        "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart", "rds:DescribeDBInstances",
        "s3:GetObject", "s3:PutObject",
      ], action) && !startswith(action, "rds:") && !startswith(action, "s3:")
    ]]))
    error_message = "Deployer must not upload images, access RDS, or access Terraform state."
  }

  assert {
    condition = (
      aws_eks_access_entry.deployer.cluster_name == var.cluster_name &&
      aws_eks_access_entry.deployer.principal_arn == aws_iam_role.deployer.arn &&
      aws_eks_access_entry.deployer.type == "STANDARD" &&
      aws_eks_access_policy_association.deployer.policy_arn == "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy" &&
      one(aws_eks_access_policy_association.deployer.access_scope).type == "namespace" &&
      toset(one(aws_eks_access_policy_association.deployer.access_scope).namespaces) == toset(["oficina-mecanica"])
    )
    error_message = "EKS access must grant AmazonEKSEditPolicy only in the oficina-mecanica namespace."
  }

  assert {
    condition     = output.deployer_role_arn == aws_iam_role.deployer.arn
    error_message = "Deployer output must expose the managed role ARN."
  }
}

run "reject_environment_trust_mismatch" {
  command = plan
  variables { github_environment = "producao" }
  expect_failures = [var.github_environment]
}

run "reject_wrong_deployer_boundary" {
  command = plan
  variables { permissions_boundary_arn = "arn:aws:iam::123456789012:policy/oficina-mecanica-homologacao-runtime-boundary" }
  expect_failures = [var.permissions_boundary_arn]
}
