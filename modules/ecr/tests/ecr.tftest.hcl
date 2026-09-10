mock_provider "aws" {
  override_during = plan
}

override_resource {
  target          = aws_ecr_repository.api
  override_during = plan
  values = {
    arn            = "arn:aws:ecr:us-east-1:123456789012:repository/oficina-mecanica-api"
    repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/oficina-mecanica-api"
  }
}

variables {
  repository_name = "oficina-mecanica-api"
  tags            = { Owner = "platform" }
}

run "repository_is_immutable_scanned_encrypted_and_recoverable" {
  command = plan

  assert {
    condition = (
      aws_ecr_repository.api.name == "oficina-mecanica-api" &&
      aws_ecr_repository.api.image_tag_mutability == "IMMUTABLE" &&
      aws_ecr_repository.api.force_delete == false &&
      one(aws_ecr_repository.api.image_scanning_configuration).scan_on_push &&
      one(aws_ecr_repository.api.encryption_configuration).encryption_type == "AES256"
    )
    error_message = "The API repository must be deterministic, immutable, scanned, encrypted, and protected from forced deletion."
  }

  assert {
    condition = (
      aws_ecr_lifecycle_policy.api.repository == aws_ecr_repository.api.name &&
      length(jsondecode(aws_ecr_lifecycle_policy.api.policy).rules) == 2 &&
      one([for rule in jsondecode(aws_ecr_lifecycle_policy.api.policy).rules : rule if rule.rulePriority == 1]).selection == {
        tagStatus     = "tagged"
        tagPrefixList = ["sha-"]
        countType     = "imageCountMoreThan"
        countNumber   = 100
      } &&
      one([for rule in jsondecode(aws_ecr_lifecycle_policy.api.policy).rules : rule if rule.rulePriority == 2]).selection == {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 7
      }
    )
    error_message = "Lifecycle must retain 100 sha-* images and expire only untagged images older than seven days."
  }

  assert {
    condition = (
      output.repository_arn == aws_ecr_repository.api.arn &&
      output.repository_name == aws_ecr_repository.api.name &&
      output.repository_url == aws_ecr_repository.api.repository_url
    )
    error_message = "ECR outputs must expose the managed repository ARN, name, and URL."
  }
}

run "reject_empty_repository_name" {
  command = plan
  variables { repository_name = " " }
  expect_failures = [var.repository_name]
}
