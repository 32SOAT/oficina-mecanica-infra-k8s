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

arguments=("$@")
for ((index = 0; index < ${#arguments[@]}; index++)); do
  if [[ "${arguments[index]}" == 'state' && "${arguments[index + 1]:-}" == 'list' ]]; then
    printf '%s\n' 'aws_vpc.this' 'aws_subnet.private[0]'
    exit 0
  fi
  if [[ "${arguments[index]}" == 'state' && "${arguments[index + 1]:-}" == 'pull' ]]; then
    printf '%s\n' 'SENSITIVE_STATE_VALUE'
    exit 0
  fi
done

for argument in "$@"; do
  if [[ "${argument}" == 'providers' ]]; then
    printf '%s\n' 'provider[registry.terraform.io/hashicorp/aws]'
    exit 0
  fi
done

for argument in "$@"; do
  if [[ "${argument}" == 'output' ]]; then
    printf '%s\n' 'safe-output'
    exit 0
  fi
done

for argument in "$@"; do
  if [[ "${argument}" == 'plan' ]]; then
    exit "${FAKE_DRIFT_EXIT_STATUS:?}"
  fi
done
EOF
chmod +x "${test_bin}/terraform"

PATH="${test_bin}:${PATH}"
export PATH
FAKE_TERRAFORM_ARGUMENTS="${terraform_arguments}"
TF_BACKEND_BUCKET='oficina-terraform-state'
TF_BACKEND_REGION='us-east-1'
TF_BACKEND_KMS_KEY_ID='alias/oficina-terraform'
TF_EXPECTED_AWS_ACCOUNT_ID='123456789012'
export FAKE_TERRAFORM_ARGUMENTS TF_BACKEND_BUCKET TF_BACKEND_REGION
export TF_BACKEND_KMS_KEY_ID TF_EXPECTED_AWS_ACCOUNT_ID
cd "${test_bin}"

# A missing, non-regular, stackless, or cross-stack plan must never reach apply.
if TF_ALLOW_LOCAL_APPLY=1 bash "${repo_root}/scripts/terraform-apply.sh" homologacao "${plan_file}"; then
  printf 'FAIL: apply sem plan foi aceito\n' >&2
  exit 1
fi

: >"${plan_file}"
printf '%s\n' 'homologacao' >"${plan_file}.stack"
if bash "${repo_root}/scripts/terraform-apply.sh" homologacao "${plan_file}"; then
  printf 'FAIL: apply local sem autorizacao foi aceito\n' >&2
  exit 1
fi

rm -f -- "${plan_file}.stack"
if TF_ALLOW_LOCAL_APPLY=1 bash "${repo_root}/scripts/terraform-apply.sh" homologacao "${plan_file}"; then
  printf 'FAIL: apply sem marker foi aceito\n' >&2
  exit 1
fi

printf '%s\n' 'producao' >"${plan_file}.stack"
if TF_ALLOW_LOCAL_APPLY=1 bash "${repo_root}/scripts/terraform-apply.sh" homologacao "${plan_file}"; then
  printf 'FAIL: apply com marker de outro stack foi aceito\n' >&2
  exit 1
fi

irregular_plan="${test_bin}/irregular.tfplan"
ln -s "${plan_file}" "${irregular_plan}"
printf '%s\n' 'homologacao' >"${irregular_plan}.stack"
if TF_ALLOW_LOCAL_APPLY=1 bash "${repo_root}/scripts/terraform-apply.sh" homologacao "${irregular_plan}"; then
  printf 'FAIL: apply com plan irregular foi aceito\n' >&2
  exit 1
fi

printf '%s\n' 'producao' >"${plan_file}.stack"
if CI=true AWS_ACCOUNT_ID='123456789012' GITHUB_REF='refs/heads/homolog' \
  bash "${repo_root}/scripts/terraform-apply.sh" producao "${plan_file}"; then
  printf 'FAIL: apply de producao fora de main foi aceito\n' >&2
  exit 1
fi

printf '%s\n' 'homologacao' >"${plan_file}.stack"
TF_ALLOW_LOCAL_APPLY=1 bash "${repo_root}/scripts/terraform-apply.sh" homologacao "${plan_file}"
grep -Fxq -- "-chdir=${repo_root}/environments/homologacao" "${terraform_arguments}"
grep -Fxq -- 'apply' "${terraform_arguments}"
grep -Fxq -- '-input=false' "${terraform_arguments}"
grep -Fxq -- "${plan_file}" "${terraform_arguments}"

# An arbitrary output name must be refused before it can reach Terraform.
if bash "${repo_root}/scripts/terraform-output.sh" shared db_password; then
  printf 'FAIL: output fora da allowlist foi aceito\n' >&2
  exit 1
fi
bash "${repo_root}/scripts/terraform-output.sh" shared repository_url >"${test_bin}/output"
test "$(<"${test_bin}/output")" = 'safe-output'
grep -Fxq -- 'output' "${terraform_arguments}"
grep -Fxq -- '-json' "${terraform_arguments}"
grep -Fxq -- 'repository_url' "${terraform_arguments}"

# Terraform's detailed exit status is the drift result; no apply is permitted.
FAKE_DRIFT_EXIT_STATUS=0
export FAKE_DRIFT_EXIT_STATUS
bash "${repo_root}/scripts/terraform-drift.sh" shared
FAKE_DRIFT_EXIT_STATUS=2
export FAKE_DRIFT_EXIT_STATUS
set +e
bash "${repo_root}/scripts/terraform-drift.sh" shared
drift_status=$?
set -e
test "${drift_status}" -eq 2
grep -Fxq -- 'plan' "${terraform_arguments}"
grep -Fxq -- '-refresh-only' "${terraform_arguments}"
grep -Fxq -- '-detailed-exitcode' "${terraform_arguments}"

# Audit output is limited to safe metadata and resource addresses, never pulled state.
bash "${repo_root}/scripts/terraform-state-audit.sh" shared >"${test_bin}/state-audit"
grep -Fxq -- 'aws_vpc.this' "${test_bin}/state-audit"
grep -Fxq -- 'aws_subnet.private[0]' "${test_bin}/state-audit"
grep -Fq -- 'provider[registry.terraform.io/hashicorp/aws]' "${test_bin}/state-audit"
if grep -Fq -- 'SENSITIVE_STATE_VALUE' "${test_bin}/state-audit"; then
  printf 'FAIL: auditoria imprimiu state completo\n' >&2
  exit 1
fi
if grep -Fxq -- 'pull' "${terraform_arguments}"; then
  printf 'FAIL: auditoria chamou state pull\n' >&2
  exit 1
fi
