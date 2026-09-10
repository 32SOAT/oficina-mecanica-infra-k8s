#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_bin="$(mktemp -d)"
terraform_arguments="${test_bin}/terraform-arguments"
plan_file="${test_bin}/homologacao.tfplan"
cleanup() {
  local status=$?
  rm -rf "${test_bin}"
  exit "${status}"
}
trap cleanup EXIT

cat >"${test_bin}/aws" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' '123456789012'
EOF
chmod +x "${test_bin}/aws"

cat >"${test_bin}/terraform" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$@" >>"${FAKE_TERRAFORM_ARGUMENTS:?}"

for argument in "$@"; do
  if [[ "${argument}" == 'show' ]]; then
    [[ "$1" == "-chdir=${FAKE_EXPECTED_SHOW_DIRECTORY:?}" ]] || {
      printf 'FAIL: show deve carregar providers do stack\n' >&2
      exit 42
    }
    [[ "$4" == "${FAKE_EXPECTED_SHOW_PLAN:?}" ]] || {
      printf 'FAIL: show deve receber o caminho absoluto normalizado do plan\n' >&2
      exit 43
    }
    cat "${FAKE_TERRAFORM_SHOW_JSON:?}"
    exit 0
  fi
done

for argument in "$@"; do
  if [[ "${argument}" == 'init' ]]; then
    exit "${FAKE_INIT_EXIT_STATUS:-0}"
  fi
done

for argument in "$@"; do
  if [[ "${argument}" == 'plan' ]]; then
    for plan_argument in "$@"; do
      case "${plan_argument}" in
        -out=*) : >"${plan_argument#-out=}" ;;
      esac
    done
    exit "${FAKE_PLAN_EXIT_STATUS:?}"
  fi
done
EOF
chmod +x "${test_bin}/terraform"

PATH="${test_bin}:${PATH}"
export PATH
FAKE_TERRAFORM_ARGUMENTS="${terraform_arguments}"
FAKE_TERRAFORM_SHOW_JSON="${repo_root}/tests/fixtures/plan-safe.json"
TF_BACKEND_BUCKET='oficina-terraform-state'
TF_BACKEND_REGION='us-east-1'
TF_BACKEND_KMS_KEY_ID='alias/oficina-terraform'
TF_EXPECTED_AWS_ACCOUNT_ID='123456789012'
export FAKE_TERRAFORM_ARGUMENTS FAKE_TERRAFORM_SHOW_JSON
export TF_BACKEND_BUCKET TF_BACKEND_REGION TF_BACKEND_KMS_KEY_ID
export TF_EXPECTED_AWS_ACCOUNT_ID
cd "${test_bin}"

# A wrapper that treats Terraform exit 2 as an error, loses the target stack,
# or leaves a stale metadata file after failure must fail this test.
FAKE_PLAN_EXIT_STATUS=0
export FAKE_PLAN_EXIT_STATUS
bash "${repo_root}/scripts/terraform-plan.sh" homologacao "${plan_file}"
test -f "${plan_file}"
test "$(<"${plan_file}.stack")" = 'homologacao'

FAKE_PLAN_EXIT_STATUS=2
export FAKE_PLAN_EXIT_STATUS
bash "${repo_root}/scripts/terraform-plan.sh" homologacao "${plan_file}"
test "$(<"${plan_file}.stack")" = 'homologacao'

printf '%s\n' 'stale' >"${plan_file}.stack"
FAKE_INIT_EXIT_STATUS=1
export FAKE_INIT_EXIT_STATUS
if bash "${repo_root}/scripts/terraform-plan.sh" homologacao "${plan_file}"; then
  printf 'FAIL: inicializacao com erro foi aceita\n' >&2
  exit 1
fi
test ! -e "${plan_file}.stack"

FAKE_INIT_EXIT_STATUS=0
export FAKE_INIT_EXIT_STATUS
printf '%s\n' 'stale' >"${plan_file}.stack"
FAKE_PLAN_EXIT_STATUS=1
export FAKE_PLAN_EXIT_STATUS
set +e
bash "${repo_root}/scripts/terraform-plan.sh" homologacao "${plan_file}"
plan_error_status=$?
set -e
if [[ "${plan_error_status}" -ne 1 ]]; then
  printf 'FAIL: plan com erro foi aceito\n' >&2
  exit 1
fi
test ! -e "${plan_file}.stack"

grep -Fxq -- "-chdir=${repo_root}/environments/homologacao" "${terraform_arguments}"
grep -Fxq -- 'plan' "${terraform_arguments}"
grep -Fxq -- '-input=false' "${terraform_arguments}"
grep -Fxq -- '-lock-timeout=5m' "${terraform_arguments}"
grep -Fxq -- '-detailed-exitcode' "${terraform_arguments}"
grep -Fxq -- "-out=${plan_file}" "${terraform_arguments}"

bash "${repo_root}/scripts/terraform-plan-policy.sh" homologacao "${repo_root}/tests/fixtures/plan-safe.json"
if bash "${repo_root}/scripts/terraform-plan-policy.sh" producao "${repo_root}/tests/fixtures/plan-production-delete.json"; then
  printf 'FAIL: replacement destrutivo em producao foi aceito\n' >&2
  exit 1
fi

endpoint_fixture="${test_bin}/plan-production-public-endpoint.json"
printf '%s\n' '{"resource_changes":[{"type":"aws_eks_cluster","change":{"actions":["update"],"after":{"vpc_config":[{"public_access_cidrs":["0.0.0.0/0"]}]}}}]}' >"${endpoint_fixture}"
if bash "${repo_root}/scripts/terraform-plan-policy.sh" producao "${endpoint_fixture}"; then
  printf 'FAIL: endpoint EKS aberto em producao foi aceito\n' >&2
  exit 1
fi

binary_plan="${test_bin}/saved.tfplan"
printf 'binary-plan\n' >"${binary_plan}"
FAKE_EXPECTED_SHOW_DIRECTORY="${repo_root}/environments/homologacao"
FAKE_EXPECTED_SHOW_PLAN="${binary_plan}"
export FAKE_EXPECTED_SHOW_DIRECTORY FAKE_EXPECTED_SHOW_PLAN
bash "${repo_root}/scripts/terraform-plan-policy.sh" homologacao "${binary_plan}"
bash "${repo_root}/scripts/terraform-plan-policy.sh" homologacao './saved.tfplan'
FAKE_EXPECTED_SHOW_DIRECTORY="${repo_root}/environments/producao"
bash "${repo_root}/scripts/terraform-plan-policy.sh" producao './saved.tfplan'
grep -Fxq -- 'show' "${terraform_arguments}"
grep -Fxq -- '-json' "${terraform_arguments}"
grep -Fxq -- "${binary_plan}" "${terraform_arguments}"
