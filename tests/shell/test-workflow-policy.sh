#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow_dir="${repo_root}/.github/workflows"
change_classifier="${repo_root}/scripts/classify-terraform-changes.sh"

required_workflows=(
  terraform-ci.yml
  terraform-deploy.yml
  terraform-drift.yml
  terraform-destroy.yml
  kubernetes-ci.yml
  kubernetes-deploy.yml
)

for workflow in "${required_workflows[@]}"; do
  [[ -f "${workflow_dir}/${workflow}" ]] || {
    printf 'Workflow obrigatório ausente: %s\n' "${workflow}" >&2
    exit 1
  }
done

kubernetes_classification="$(printf '%s\n' 'scripts/kubernetes-render.sh' | bash "${change_classifier}")"
grep -Fxq 'terraform_changed=false' <<< "${kubernetes_classification}"
grep -Fxq 'shared_changed=false' <<< "${kubernetes_classification}"
grep -Fxq 'environment_changed=false' <<< "${kubernetes_classification}"

terraform_classification="$(printf '%s\n' 'scripts/terraform-plan.sh' | bash "${change_classifier}")"
grep -Fxq 'terraform_changed=true' <<< "${terraform_classification}"
grep -Fxq 'shared_changed=true' <<< "${terraform_classification}"
grep -Fxq 'environment_changed=true' <<< "${terraform_classification}"

classifier_classification="$(printf '%s\n' 'scripts/classify-terraform-changes.sh' | bash "${change_classifier}")"
grep -Fxq 'terraform_changed=true' <<< "${classifier_classification}"
grep -Fxq 'shared_changed=true' <<< "${classifier_classification}"
grep -Fxq 'environment_changed=true' <<< "${classifier_classification}"

if rg -n 'scripts/\*\*' "${workflow_dir}/terraform-ci.yml" "${workflow_dir}/terraform-deploy.yml"; then
  printf 'Path genérico de scripts mistura mudanças Kubernetes e Terraform.\n' >&2
  exit 1
fi

if rg -n 'AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|docker (build|tag|push)' "${workflow_dir}"; then
  printf 'Credencial persistente ou operação Docker encontrada em workflow Terraform.\n' >&2
  exit 1
fi

if rg -n 'uses:[[:space:]]+[^[:space:]]+@v[0-9]' "${workflow_dir}"; then
  printf 'Action com tag flutuante encontrada.\n' >&2
  exit 1
fi

direct_apply_pattern='terraform[[:space:]\\]+(?:-chdir(?:=[^[:space:]\\]+|[[:space:]\\]+[^[:space:]\\]+)[[:space:]\\]+)?apply'
if ! printf '%s %s\n' terraform "\\" '  -chdir=environments/producao' "\\" '  apply saved.tfplan' '' | rg -Uq "${direct_apply_pattern}"; then
  printf 'O scanner não detecta terraform apply multiline com -chdir.\n' >&2
  exit 1
fi
if rg -U -n "${direct_apply_pattern}" "${workflow_dir}"; then
  printf 'Apply direto encontrado fora do wrapper.\n' >&2
  exit 1
fi

if rg -n 'vars\.GITHUB_OIDC_PROVIDER_ARN' "${workflow_dir}"; then
  printf 'Variável GitHub reservada usada para o ARN OIDC.\n' >&2
  exit 1
fi

if rg -n '\x60' "${workflow_dir}"; then
  printf 'Backtick executável encontrado em workflow.\n' >&2
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
kubernetes_ci_workflow="${workflow_dir}/kubernetes-ci.yml"

rg -q 'name:[[:space:]]+terraform / gate' "${ci_workflow}"
rg -q 'pull_request:' "${ci_workflow}"
rg -q -- '- homolog' "${ci_workflow}"
rg -q -- '- main' "${ci_workflow}"
rg -q 'github.event.pull_request.head.repo.full_name == github.repository' "${ci_workflow}"
rg -q 'TRIVY_VERSION:[[:space:]]+0\.74\.0' "${ci_workflow}"
rg -q 'TRIVY_LINUX_AMD64_SHA256:[[:space:]]+2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a' "${ci_workflow}"
rg -q 'github.com/rhysd/actionlint/cmd/actionlint@v1\.7\.12' "${ci_workflow}"
rg -q 'Install ripgrep' "${ci_workflow}"
rg -q 'apt-get install -y ripgrep' "${ci_workflow}"
rg -q 'terraform_changed:' "${ci_workflow}"
rg -q "needs\.static-check\.outputs\.terraform_changed == 'true'" "${ci_workflow}"
rg -q 'PLAN_REQUIRED:' "${ci_workflow}"
rg -q 'SHARED_PLAN_REQUIRED:' "${ci_workflow}"
rg -q 'Configuração obrigatória ausente' "${ci_workflow}"
rg -q 'name: Diagnose OIDC context' "${ci_workflow}"
rg -q 'GITHUB_REPOSITORY=\$\{GITHUB_REPOSITORY\}' "${ci_workflow}"
rg -q 'GITHUB_EVENT_NAME=\$\{GITHUB_EVENT_NAME\}' "${ci_workflow}"
rg -q 'GITHUB_BASE_REF=\$\{GITHUB_BASE_REF\}' "${ci_workflow}"
rg -q 'GITHUB_HEAD_REF=\$\{GITHUB_HEAD_REF\}' "${ci_workflow}"
rg -q 'BASE_REF: \$\{\{ github.base_ref \}\}' "${kubernetes_ci_workflow}"
rg -q 'HEAD_REF: \$\{\{ github.head_ref \}\}' "${kubernetes_ci_workflow}"
rg -q '"\$\{BASE_REF\}" "\$\{HEAD_REF\}"' "${kubernetes_ci_workflow}"
direct_ref_usage="$(rg -n '\$\{\{ github\.(base_ref|head_ref) \}\}' "${kubernetes_ci_workflow}" | rg -v '^[0-9]+:[[:space:]]+(BASE_REF|HEAD_REF):' || true)"
if [[ -n "${direct_ref_usage}" ]]; then
  printf 'Ref GitHub usada diretamente em script.\n' >&2
  exit 1
fi

if rg -n "&&[[:space:]]*'?(producao|main)'?[[:space:]]*\|\|[[:space:]]*'?(homologacao|homolog)'?" "${workflow_dir}"; then
  printf 'Seleção ambígua com &&/|| encontrada.\n' >&2
  exit 1
fi

rg -q "if:[[:space:]]+vars.TF_DEPLOY_ENABLED == 'true'" "${deploy_workflow}"
rg -q 'cancel-in-progress:[[:space:]]+false' "${deploy_workflow}"
rg -q 'scripts/terraform-plan.sh' "${deploy_workflow}"
rg -q 'scripts/terraform-plan-policy.sh' "${deploy_workflow}"
rg -q 'scripts/terraform-apply.sh' "${deploy_workflow}"

rg -q 'schedule:' "${drift_workflow}"
rg -q 'workflow_dispatch:' "${drift_workflow}"
rg -q 'scripts/terraform-drift.sh' "${drift_workflow}"
# Parse the matrix and job contract: scheduled runs retain refs/heads/main even
# when checkout selects homolog. The drift environment must be distinct from
# the apply environment and its credentials must be the read-only plan role.
ruby - "${drift_workflow}" <<'RUBY'
require "yaml"
workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
job = workflow.fetch("jobs").fetch("drift")
abort "Drift must execute only from main" unless job.fetch("if", "") == "github.ref == 'refs/heads/main'"
abort "Drift must use its separate Environment" unless job.fetch("environment") == '${{ matrix.environment }}'
expected = [
  {"stack" => "homologacao", "ref" => "homolog", "environment" => "drift-homologacao"},
  {"stack" => "producao", "ref" => "main", "environment" => "drift-producao"}
]
abort "Drift branch/environment matrix changed" unless job.fetch("strategy").fetch("matrix").fetch("include") == expected
credentials = job.fetch("steps").find { |step| step.fetch("uses", "").start_with?("aws-actions/configure-aws-credentials@") }
abort "Drift requires read-only credentials" unless credentials.fetch("with").fetch("role-to-assume") == '${{ vars.TF_PLAN_ROLE_ARN }}'
abort "Drift must serialize with deploy" unless job.fetch("concurrency").fetch("group") == 'terraform-${{ matrix.stack }}'
RUBY
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
  rg -q 'vars\.AWS_OIDC_PROVIDER_ARN' "${workflow}"
done

for variable in cluster_endpoint_public_access_cidrs cluster_permissions_boundary_arn node_permissions_boundary_arn deployer_permissions_boundary_arn; do
  rg -q "TF_VAR_${variable}=" "${ci_workflow}"
done

kubernetes_ci_workflow="${workflow_dir}/kubernetes-ci.yml"
kubernetes_deploy_workflow="${workflow_dir}/kubernetes-deploy.yml"
rg -q 'name:[[:space:]]+kubernetes / gate' "${kubernetes_ci_workflow}"
rg -q 'pull_request:' "${kubernetes_ci_workflow}"
rg -q 'kubernetes-validate.sh' "${kubernetes_ci_workflow}"
rg -q 'kubernetes-promotion-policy.sh' "${kubernetes_ci_workflow}"
grep -Fq 'kubernetes_paths=()' "${kubernetes_ci_workflow}"
# These patterns must remain literal because they inspect workflow source.
# shellcheck disable=SC2016
grep -Fq 'kubernetes_paths+=("${changed_path}")' "${kubernetes_ci_workflow}"
# shellcheck disable=SC2016
grep -Fq '"${kubernetes_paths[@]}"' "${kubernetes_ci_workflow}"
rg -q 'workflow_dispatch:' "${kubernetes_deploy_workflow}"
rg -q 'KUBERNETES_HOMOLOGACAO_DEPLOY_ENABLED' "${kubernetes_deploy_workflow}"
rg -q 'KUBERNETES_PRODUCAO_DEPLOY_ENABLED' "${kubernetes_deploy_workflow}"
rg -q 'scripts/kubernetes-deploy.sh' "${kubernetes_deploy_workflow}"
if rg -n 'docker (build|push)|terraform (apply|plan)|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY' "${kubernetes_ci_workflow}" "${kubernetes_deploy_workflow}"; then
  printf 'Workflow Kubernetes contém build, Terraform ou credencial persistente.\n' >&2
  exit 1
fi
if rg -n 'image_(tag|digest|ref):' "${kubernetes_deploy_workflow}"; then
  printf 'Workflow Kubernetes aceita imagem como input.\n' >&2
  exit 1
fi

if rg -n -- '-plugin-dir=.*\.terraform/providers' "${repo_root}/tests/shell/test-terraform-plan-policy-integration.sh"; then
  printf 'Teste Terraform reutiliza pacote extraído fora do cache verificado.\n' >&2
  exit 1
fi

for workflow in "${deploy_workflow}" "${drift_workflow}" "${destroy_workflow}"; do
  rg -q 'TF_VAR_cluster_endpoint_public_access_cidrs:' "${workflow}"
  rg -q 'TF_VAR_cluster_permissions_boundary_arn:' "${workflow}"
  rg -q 'TF_VAR_node_permissions_boundary_arn:' "${workflow}"
  rg -q 'TF_VAR_deployer_permissions_boundary_arn:' "${workflow}"
done

rg -q 'TF_VAR_publisher_permissions_boundary_arn:' "${ci_workflow}"
rg -q 'TF_VAR_publisher_permissions_boundary_arn:' "${deploy_workflow}"
rg -q 'TF_VAR_publisher_permissions_boundary_arn:' "${destroy_workflow}"

oidc_jobs="$(rg -c 'configure-aws-credentials@' "${workflow_dir}" | awk -F: '{ total += $2 } END { print total + 0 }')"
identity_checks="$(rg -c 'arn:aws:sts::\$\{AWS_ACCOUNT_ID\}:assumed-role/\$\{role_name\}/gha-\$\{GITHUB_RUN_ID\}' "${workflow_dir}" | awk -F: '{ total += $2 } END { print total + 0 }')"
[[ "${oidc_jobs}" -eq 8 ]]
[[ "${identity_checks}" -eq "${oidc_jobs}" ]] || {
  printf 'Cada job OIDC deve validar a conta e a role STS exatas.\n' >&2
  exit 1
}

printf 'Workflow policy tests passed.\n'
