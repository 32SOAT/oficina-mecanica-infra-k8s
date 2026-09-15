# This composition test catches use of unknown subnet IDs as for_each keys.
mock_provider "aws" {
  override_during = plan

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }

  mock_data "aws_subnet" {
    defaults = {
      vpc_id = "vpc-mocked"
    }
  }
}

run "network_outputs_can_feed_first_eks_plan" {
  command = plan

  module {
    source = "./tests/fixtures/network-eks"
  }

  assert {
    condition     = output.cluster_name == "oficina-mecanica-homologacao"
    error_message = "The EKS module must plan when private subnet IDs come directly from a not-yet-created network module."
  }
}
