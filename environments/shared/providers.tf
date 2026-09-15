provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Project     = "oficina-mecanica"
      Environment = "shared"
      ManagedBy   = "Terraform"
      Repository  = "oficina-mecanica-infra-k8s"
    })
  }
}
