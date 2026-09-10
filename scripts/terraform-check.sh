#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
# Source path is derived from BASH_SOURCE and unavailable to static analysis.
# shellcheck disable=SC1091
source "${script_dir}/lib/terraform-common.sh"

require_command terraform
require_command shellcheck
cd "${repo_root}"

terraform fmt -check -recursive
# Every root with native Terraform tests, including administrative bootstraps
# and reusable modules. All providers are pinned; no AWS/backend is used.
test_roots=(
  bootstrap/backend bootstrap/identity
  modules/network modules/eks modules/ecr modules/platform-contract
  modules/api-publisher-identity modules/api-deployer-identity
  environments/shared environments/homologacao environments/producao
)
for root in "${test_roots[@]}"; do
  terraform -chdir="${repo_root}/${root}" init -backend=false -input=false -lockfile=readonly
  terraform -chdir="${repo_root}/${root}" validate
  terraform -chdir="${repo_root}/${root}" test
done

for test_script in tests/shell/test-*.sh; do
  bash "${test_script}"
done

shellcheck scripts/*.sh scripts/lib/*.sh tests/shell/test-*.sh
