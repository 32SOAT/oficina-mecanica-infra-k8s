locals {
  stacks       = toset(["shared", "homologacao", "producao"])
  environments = setsubtract(local.stacks, ["shared"])
  issuer       = "token.actions.githubusercontent.com"
  repository   = "repo:${var.github_organization}/${var.github_repository}"
  tags = merge(var.tags, {
    Project   = var.project_name
    ManagedBy = "Terraform"
    Component = "terraform-identity"
  })
  subjects = merge(
    { plan = "${local.repository}:pull_request" },
    { for stack in local.stacks : "${stack}-apply" => "${local.repository}:environment:${stack}" },
    { for stack in local.stacks : "${stack}-destroy" => "${local.repository}:environment:${stack}" }
  )
  trust_policies = { for name, subject in local.subjects : name => jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = { StringEquals = {
        "${local.issuer}:aud" = "sts.amazonaws.com"
        "${local.issuer}:sub" = subject
      } }
    }]
  }) }
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://${local.issuer}"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  tags            = local.tags
}

resource "aws_iam_role" "plan" {
  name                 = "${var.project_name}-terraform-plan"
  description          = "Pull-request Terraform plans; writes only backend lockfiles."
  assume_role_policy   = local.trust_policies.plan
  max_session_duration = 3600
  tags                 = local.tags
}

resource "aws_iam_role" "apply" {
  for_each             = local.stacks
  name                 = "${var.project_name}-terraform-${each.key}-apply"
  description          = "Terraform apply for ${each.key}, gated by its GitHub Environment."
  assume_role_policy   = local.trust_policies["${each.key}-apply"]
  max_session_duration = 3600
  tags                 = merge(local.tags, { Stack = each.key, Operation = "apply" })
}

resource "aws_iam_role" "destroy" {
  for_each             = local.stacks
  name                 = "${var.project_name}-terraform-${each.key}-destroy"
  description          = "Manual Terraform destroy for ${each.key}, gated by its protected GitHub Environment."
  assume_role_policy   = local.trust_policies["${each.key}-destroy"]
  max_session_duration = 3600
  tags                 = merge(local.tags, { Stack = each.key, Operation = "destroy" })
}
