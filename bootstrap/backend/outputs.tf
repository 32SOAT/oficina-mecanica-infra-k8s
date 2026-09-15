output "state_bucket_name" {
  description = "S3 bucket name passed to the partial backend configuration."
  value       = aws_s3_bucket.state.bucket
}

output "state_bucket_arn" {
  description = "State bucket ARN for scoped IAM permissions."
  value       = aws_s3_bucket.state.arn
}

output "state_kms_key_arn" {
  description = "KMS key ARN used by the backend and future IAM roles."
  value       = aws_kms_key.state.arn
}
