#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
module_dir="${repo_root}/modules/api-gateway-http"

if rg -n 'aws_(apigatewayv2_domain_name|acm_certificate|route53_|wafv2_|apigatewayv2_vpc_link|cloudwatch_log_group|lb|lb_listener)' "${module_dir}"; then
  printf 'API Gateway module contains an out-of-scope resource.\n' >&2
  exit 1
fi

rg -n 'aws_apigatewayv2_api|aws_apigatewayv2_integration|aws_apigatewayv2_route|aws_apigatewayv2_stage|aws_lambda_permission' "${module_dir}" >/dev/null
printf 'API Gateway scope checks passed.\n'
