mock_provider "aws" {
  override_during = plan

  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

override_resource {
  target          = aws_apigatewayv2_api.this
  override_during = plan
  values = {
    id            = "api-mocked"
    api_endpoint  = "https://api-mocked.execute-api.us-east-1.amazonaws.com"
    execution_arn = "arn:aws:apigateway:us-east-1::/apis/api-mocked"
  }
}

override_resource {
  target          = aws_apigatewayv2_integration.lambda
  override_during = plan
  values          = { id = "integration-lambda" }
}

override_resource {
  target          = aws_apigatewayv2_integration.proxy
  override_during = plan
  values          = { id = "integration-proxy" }
}

variables {
  environment  = "homologacao"
  api_name     = "oficina-mecanica-homologacao"
  lambda_arn   = "arn:aws:lambda:us-east-1:123456789012:function:oficina-mecanica-auth-cpf-homologacao"
  nlb_hostname = "api-homologacao.elb.us-east-1.amazonaws.com"
  aws_region   = "us-east-1"
}

run "creates_http_routes_and_default_stage" {
  command = plan

  assert {
    condition = (
      aws_apigatewayv2_api.this.protocol_type == "HTTP" &&
      aws_apigatewayv2_route.lambda.route_key == "POST /auth/cpf" &&
      aws_apigatewayv2_route.proxy.route_key == "ANY /{proxy+}" &&
      aws_apigatewayv2_stage.default.name == "$default" &&
      aws_apigatewayv2_stage.default.auto_deploy
    )
    error_message = "The module must expose the required HTTP routes and an auto-deployed default stage."
  }

  assert {
    condition = (
      aws_apigatewayv2_integration.lambda.integration_uri == var.lambda_arn &&
      aws_apigatewayv2_integration.proxy.integration_uri == "http://${var.nlb_hostname}"
    )
    error_message = "Integrations must target the Lambda ARN and the HTTP NLB hostname contract."
  }

  assert {
    condition = (
      aws_lambda_permission.apigw.principal == "apigateway.amazonaws.com" &&
      aws_lambda_permission.apigw.action == "lambda:InvokeFunction" &&
      aws_lambda_permission.apigw.function_name == var.lambda_arn
    )
    error_message = "The Lambda permission must be scoped to API Gateway and the consumed Lambda ARN."
  }
}

run "exposes_only_gateway_contract_outputs" {
  command = plan

  assert {
    condition = (
      output.api_id == aws_apigatewayv2_api.this.id &&
      output.api_endpoint == aws_apigatewayv2_api.this.api_endpoint &&
      output.lambda_integration_id == aws_apigatewayv2_integration.lambda.id &&
      output.nlb_integration_id == aws_apigatewayv2_integration.proxy.id
    )
    error_message = "The module outputs must expose the API and both integration IDs."
  }
}

run "rejects_unknown_environment" {
  command = plan

  variables { environment = "staging" }

  expect_failures = [var.environment]
}
