mock_provider "aws" {
  override_during = plan
}

variables {
  environment                       = "homologacao"
  aws_region                        = "us-east-1"
  vpc_id                            = "vpc-0123456789abcdef0"
  public_subnet_ids                 = ["subnet-public-a", "subnet-public-b"]
  private_subnet_ids                = ["subnet-private-a", "subnet-private-b"]
  database_subnet_ids               = ["subnet-database-a", "subnet-database-b"]
  database_client_security_group_id = "sg-0123456789abcdef0"
  eks_cluster_name                  = "oficina-mecanica-homologacao"
  owner                             = "platform"
}

run "publishes_exact_non_sensitive_environment_contract" {
  command = plan

  assert {
    condition = toset([for parameter in aws_ssm_parameter.platform : parameter.name]) == toset([
      "/oficina/homologacao/platform/aws-region",
      "/oficina/homologacao/platform/vpc-id",
      "/oficina/homologacao/platform/public-subnet-ids",
      "/oficina/homologacao/platform/private-subnet-ids",
      "/oficina/homologacao/platform/database-subnet-ids",
      "/oficina/homologacao/platform/database-client-security-group-id",
      "/oficina/homologacao/platform/eks-cluster-name",
    ])
    error_message = "Platform contract must publish exactly the seven approved environment paths."
  }

  assert {
    condition = (
      jsondecode(aws_ssm_parameter.platform["public-subnet-ids"].value) == ["subnet-public-a", "subnet-public-b"] &&
      jsondecode(aws_ssm_parameter.platform["private-subnet-ids"].value) == ["subnet-private-a", "subnet-private-b"] &&
      jsondecode(aws_ssm_parameter.platform["database-subnet-ids"].value) == ["subnet-database-a", "subnet-database-b"]
    )
    error_message = "Subnet lists must be serialized as JSON arrays."
  }

  assert {
    condition = alltrue([for parameter in aws_ssm_parameter.platform :
      parameter.type == "String" &&
      trimspace(parameter.description) != "" &&
      parameter.tags["Owner"] == "platform" &&
      parameter.tags["Environment"] == "homologacao" &&
      parameter.tags["Source"] == "oficina-mecanica-infra-k8s"
    ])
    error_message = "Every contract parameter must be described and carry Owner, Environment, and Source tags."
  }

  assert {
    condition     = toset(output.parameter_names) == toset([for parameter in aws_ssm_parameter.platform : parameter.name])
    error_message = "Contract output must expose exactly the managed parameter names."
  }
}

run "reject_empty_scalar" {
  command = plan
  variables { vpc_id = " " }
  expect_failures = [var.vpc_id]
}

run "reject_empty_list" {
  command = plan
  variables { private_subnet_ids = [] }
  expect_failures = [var.private_subnet_ids]
}

run "reject_empty_list_element" {
  command = plan
  variables { database_subnet_ids = ["subnet-a", " "] }
  expect_failures = [var.database_subnet_ids]
}
