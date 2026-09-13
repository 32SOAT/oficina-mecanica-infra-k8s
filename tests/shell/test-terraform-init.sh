#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_bin="$(mktemp -d)"
terraform_arguments="${test_bin}/terraform-arguments"
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
printf '%s\n' "$@" >"${FAKE_TERRAFORM_ARGUMENTS:?}"
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

# Missing backend hardening, an incorrect stack path/key, or a missing CI lockfile
# safeguard must make this test fail.
env -u CI bash "${repo_root}/scripts/terraform-init.sh" homologacao

grep -Fxq -- "-chdir=${repo_root}/environments/homologacao" "${terraform_arguments}"
grep -Fxq -- 'init' "${terraform_arguments}"
grep -Fxq -- '-reconfigure' "${terraform_arguments}"
grep -Fxq -- '-input=false' "${terraform_arguments}"
grep -Fxq -- '-backend-config=bucket=oficina-terraform-state' "${terraform_arguments}"
grep -Fxq -- '-backend-config=key=oficina/infra/homologacao/terraform.tfstate' "${terraform_arguments}"
grep -Fxq -- '-backend-config=region=us-east-1' "${terraform_arguments}"
grep -Fxq -- '-backend-config=kms_key_id=alias/oficina-terraform' "${terraform_arguments}"
grep -Fxq -- '-backend-config=encrypt=true' "${terraform_arguments}"
grep -Fxq -- '-backend-config=use_lockfile=true' "${terraform_arguments}"
if grep -Fxq -- '-lockfile=readonly' "${terraform_arguments}"; then
  exit 1
fi

AWS_ACCOUNT_ID='123456789012'
export AWS_ACCOUNT_ID
CI=true bash "${repo_root}/scripts/terraform-init.sh" homologacao
grep -Fxq -- '-lockfile=readonly' "${terraform_arguments}"

unset TF_EXPECTED_AWS_ACCOUNT_ID
CI=true bash "${repo_root}/scripts/terraform-init.sh" shared
grep -Fxq -- '-backend-config=key=oficina/infra/shared/terraform.tfstate' "${terraform_arguments}"
