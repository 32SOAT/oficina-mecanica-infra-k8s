#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Source path is derived from BASH_SOURCE and unavailable to static analysis.
# shellcheck disable=SC1091
source "${script_dir}/lib/terraform-common.sh"

[[ $# -eq 1 ]] || die 'Uso: terraform-init.sh <shared|homologacao|producao>'
stack="$(validate_stack "$1")"

: "${TF_BACKEND_BUCKET:?TF_BACKEND_BUCKET deve estar definido}"
: "${TF_BACKEND_REGION:?TF_BACKEND_REGION deve estar definido}"
: "${TF_BACKEND_KMS_KEY_ID:?TF_BACKEND_KMS_KEY_ID deve estar definido}"

if [[ "${CI:-}" == 'true' ]]; then
  : "${AWS_ACCOUNT_ID:?AWS_ACCOUNT_ID deve estar definido no CI}"
  expected_aws_account_id="${AWS_ACCOUNT_ID}"
else
  : "${TF_EXPECTED_AWS_ACCOUNT_ID:?TF_EXPECTED_AWS_ACCOUNT_ID deve estar definido localmente}"
  expected_aws_account_id="${TF_EXPECTED_AWS_ACCOUNT_ID}"
fi

require_command terraform
assert_aws_identity "${expected_aws_account_id}"

terraform_arguments=(
  -chdir="$(stack_directory "${stack}")"
  init
  -reconfigure
  -input=false
  -backend-config="bucket=${TF_BACKEND_BUCKET}"
  -backend-config="key=$(state_key "${stack}")"
  -backend-config="region=${TF_BACKEND_REGION}"
  -backend-config="kms_key_id=${TF_BACKEND_KMS_KEY_ID}"
  -backend-config='encrypt=true'
  -backend-config='use_lockfile=true'
)

if [[ "${CI:-}" == 'true' ]]; then
  terraform_arguments+=(-lockfile=readonly)
fi

terraform "${terraform_arguments[@]}"
