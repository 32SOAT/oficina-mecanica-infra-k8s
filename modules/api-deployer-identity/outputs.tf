output "deployer_role_arn" {
  description = "ARN da role de deploy da API restrita ao ambiente."
  value       = aws_iam_role.deployer.arn
}
