#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT
stack_dir="${test_dir}/environments/homologacao"
mkdir -p "${stack_dir}" "${test_dir}/scripts/lib" "${test_dir}/plans with spaces"
cp "${repo_root}/scripts/terraform-plan-policy.sh" "${test_dir}/scripts/"
cp "${repo_root}/scripts/lib/terraform-common.sh" "${test_dir}/scripts/lib/"
cp "${repo_root}/tests/fixtures/saved-plan/main.tf" "${stack_dir}/"
cp "${repo_root}/environments/shared/.terraform.lock.hcl" "${stack_dir}/"

# Use the already initialized, checksum-locked provider from the full suite.
# The fixture plans only terraform_data: no AWS credentials, client or backend.
terraform -chdir="${stack_dir}" init -backend=false -input=false -lockfile=readonly \
  -plugin-dir="${repo_root}/environments/shared/.terraform/providers" >/dev/null
terraform -chdir="${stack_dir}" plan -input=false -refresh=false \
  -out="${test_dir}/plans with spaces/saved.tfplan" >/dev/null
cd "${test_dir}"
if terraform show -json 'plans with spaces/saved.tfplan' >/dev/null 2>&1; then
  printf 'FAIL: fixture não reproduziu a falta de schema fora do stack\n' >&2
  exit 1
fi
bash scripts/terraform-plan-policy.sh homologacao 'plans with spaces/saved.tfplan'
printf 'Saved-plan provider-context integration passed.\n'
