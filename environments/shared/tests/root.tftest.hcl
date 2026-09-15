mock_provider "aws" {
  override_during = plan
}

override_resource {
  target          = module.ecr.aws_ecr_repository.api
  override_during = plan
  values = {
    arn            = "arn:aws:ecr:us-east-1:123456789012:repository/oficina-mecanica-api"
    repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/oficina-mecanica-api"
  }
}

override_resource {
  target          = aws_ssm_parameter.ecr_repository_url
  override_during = plan
  values = {
    arn = "arn:aws:ssm:us-east-1:123456789012:parameter/oficina/shared/ecr/repository-url"
  }
}

override_resource {
  target          = module.api_publisher_identity.aws_iam_role.publisher
  override_during = plan
  values = {
    arn = "arn:aws:iam::123456789012:role/oficina-mecanica-shared-api-publisher"
  }
}

variables {
  aws_region                         = "us-east-1"
  github_oidc_provider_arn           = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
  publisher_permissions_boundary_arn = "arn:aws:iam::123456789012:policy/oficina-mecanica-shared-api-publisher-boundary"
}

run "shared_root_exposes_safe_wrapper_contract" {
  command = plan

  assert {
    condition     = output.repository_url == "123456789012.dkr.ecr.us-east-1.amazonaws.com/oficina-mecanica-api"
    error_message = "The shared root must expose repository_url for the guarded output wrapper."
  }

  assert {
    condition     = output.publisher_role_arn == "arn:aws:iam::123456789012:role/oficina-mecanica-shared-api-publisher"
    error_message = "The shared root must expose publisher_role_arn for the guarded output wrapper."
  }

  assert {
    condition     = aws_ssm_parameter.ecr_repository_url.name == "/oficina/shared/ecr/repository-url"
    error_message = "The shared root must publish the deterministic ECR contract without remote state."
  }
}
