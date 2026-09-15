output "api_id" {
  description = "ID do API Gateway HTTP."
  value       = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "Endpoint padrao execute-api do API Gateway."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "lambda_integration_id" {
  description = "ID da integracao POST /auth/cpf com a Lambda."
  value       = aws_apigatewayv2_integration.lambda.id
}

output "nlb_integration_id" {
  description = "ID da integracao proxy HTTP com o NLB."
  value       = aws_apigatewayv2_integration.proxy.id
}
