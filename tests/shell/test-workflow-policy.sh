#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow_dir="${repo_root}/.github/workflows"

required_workflows=(
  terraform-ci.yml
  terraform-deploy.yml
  terraform-drift.yml
  terraform-destroy.yml
)

for workflow in "${required_workflows[@]}"; do
  [[ -f "${workflow_dir}/${workflow}" ]] || {
    printf 'Workflow obrigatório ausente: %s\n' "${workflow}" >&2
    exit 1
  }
done

if rg -n 'AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|docker (build|tag|push)' "${workflow_dir}"; then
  printf 'Credencial persistente ou operação Docker encontrada em workflow Terraform.\n' >&2
  exit 1
fi

if rg -n 'uses:[[:space:]]+[^[:space:]]+@v[0-9]' "${workflow_dir}"; then
  printf 'Action com tag flutuante encontrada.\n' >&2
  exit 1
fi

if rg -n 'run:[[:space:]]+terraform apply' "${workflow_dir}"; then
  printf 'Apply direto encontrado fora do wrapper.\n' >&2
  exit 1
fi

allowed_actions='actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd|hashicorp/setup-terraform@dfe3c3f87815947d99a8997f908cb6525fc44e9e|aws-actions/configure-aws-credentials@e6de054238d6b7531b4efff3b6587d9aade6a06c'
unexpected_actions="$(rg -o 'uses:[[:space:]]+[^[:space:]]+' "${workflow_dir}" | sed -E 's/^.*uses:[[:space:]]+//' | rg -v "^(${allowed_actions})$" || true)"
[[ -z "${unexpected_actions}" ]] || {
  printf 'Action não permitida encontrada:\n%s\n' "${unexpected_actions}" >&2
  exit 1
}

ci_workflow="${workflow_dir}/terraform-ci.yml"
deploy_workflow="${workflow_dir}/terraform-deploy.yml"
drift_workflow="${workflow_dir}/terraform-drift.yml"
destroy_workflow="${workflow_dir}/terraform-destroy.yml"

rg -q 'name:[[:space:]]+terraform / gate' "${ci_workflow}"
rg -q 'pull_request:' "${ci_workflow}"
rg -q -- '- homolog' "${ci_workflow}"
rg -q -- '- main' "${ci_workflow}"
rg -q 'github.event.pull_request.head.repo.full_name == github.repository' "${ci_workflow}"
rg -q 'TRIVY_VERSION:[[:space:]]+0\.74\.0' "${ci_workflow}"
rg -q 'TRIVY_LINUX_AMD64_SHA256:[[:space:]]+2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a' "${ci_workflow}"

rg -q "if:[[:space:]]+vars.TF_DEPLOY_ENABLED == 'true'" "${deploy_workflow}"
rg -q 'cancel-in-progress:[[:space:]]+false' "${deploy_workflow}"
rg -q 'scripts/terraform-plan.sh' "${deploy_workflow}"
rg -q 'scripts/terraform-plan-policy.sh' "${deploy_workflow}"
rg -q 'scripts/terraform-apply.sh' "${deploy_workflow}"

rg -q 'schedule:' "${drift_workflow}"
rg -q 'workflow_dispatch:' "${drift_workflow}"
rg -q 'scripts/terraform-drift.sh' "${drift_workflow}"
if rg -q 'terraform-apply.sh|terraform apply' "${drift_workflow}"; then
  printf 'O workflow de drift não pode aplicar mudanças.\n' >&2
  exit 1
fi

rg -q 'workflow_dispatch:' "${destroy_workflow}"
rg -q 'confirm_stack' "${destroy_workflow}"
rg -q 'ALLOW_PRODUCTION_DESTROY' "${destroy_workflow}"
rg -q 'TF_DESTROY_ROLE_ARN' "${destroy_workflow}"

for workflow in "${ci_workflow}" "${deploy_workflow}" "${drift_workflow}" "${destroy_workflow}"; do
  rg -q 'TF_BACKEND_BUCKET:' "${workflow}"
  rg -q 'TF_BACKEND_REGION:' "${workflow}"
  rg -q 'TF_BACKEND_KMS_KEY_ID:' "${workflow}"
  rg -q 'AWS_ACCOUNT_ID:' "${workflow}"
  rg -q 'TF_VAR_github_oidc_provider_arn:' "${workflow}"
done

for workflow in "${ci_workflow}" "${deploy_workflow}" "${drift_workflow}" "${destroy_workflow}"; do
  rg -q 'TF_VAR_cluster_endpoint_public_access_cidrs:' "${workflow}"
  rg -q 'TF_VAR_cluster_permissions_boundary_arn:' "${workflow}"
  rg -q 'TF_VAR_node_permissions_boundary_arn:' "${workflow}"
  rg -q 'TF_VAR_deployer_permissions_boundary_arn:' "${workflow}"
done

rg -q 'TF_VAR_publisher_permissions_boundary_arn:' "${ci_workflow}"
rg -q 'TF_VAR_publisher_permissions_boundary_arn:' "${deploy_workflow}"
rg -q 'TF_VAR_publisher_permissions_boundary_arn:' "${destroy_workflow}"

printf 'Workflow policy tests passed.\n'
