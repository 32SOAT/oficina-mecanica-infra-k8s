terraform {
  required_version = "= 1.16.1"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.100.0"
    }
  }
}

# Only the built-in provider has a resource. The saved configuration still
# requires the AWS schema to show the plan; no AWS provider client is used.
resource "terraform_data" "fixture" {
  input = "safe-local-fixture"
}
