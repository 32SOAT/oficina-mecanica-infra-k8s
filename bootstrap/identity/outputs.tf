output "github_oidc_provider_arn" {
  description = "GitHub OIDC provider reused by publisher/deployer identity modules."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "plan_role_arn" {
  description = "PR-only Terraform plan role."
  value       = aws_iam_role.plan.arn
}

output "shared_apply_role_arn" {
  description = "Apply role for the shared GitHub Environment."
  value       = aws_iam_role.apply["shared"].arn
}

output "homologacao_apply_role_arn" {
  description = "Apply role for the homologacao GitHub Environment."
  value       = aws_iam_role.apply["homologacao"].arn
}

output "producao_apply_role_arn" {
  description = "Apply role for the producao GitHub Environment."
  value       = aws_iam_role.apply["producao"].arn
}

output "shared_destroy_role_arn" {
  description = "Separate destroy role for the shared GitHub Environment."
  value       = aws_iam_role.destroy["shared"].arn
}

output "homologacao_destroy_role_arn" {
  description = "Separate destroy role for the homologacao GitHub Environment."
  value       = aws_iam_role.destroy["homologacao"].arn
}

output "producao_destroy_role_arn" {
  description = "Separate destroy role for the producao GitHub Environment."
  value       = aws_iam_role.destroy["producao"].arn
}
