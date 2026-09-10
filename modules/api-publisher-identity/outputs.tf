output "publisher_role_arn" {
  description = "ARN da role exclusiva de publicacao manual da API."
  value       = aws_iam_role.publisher.arn
}
