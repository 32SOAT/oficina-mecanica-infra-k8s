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
for stack in shared homologacao producao; do
  stack_dir="$(stack_directory "${stack}")"
  terraform -chdir="${stack_dir}" init -backend=false -input=false
  terraform -chdir="${stack_dir}" validate
  terraform -chdir="${stack_dir}" test
done

for test_script in tests/shell/test-*.sh; do
  bash "${test_script}"
done

shellcheck scripts/*.sh scripts/lib/*.sh tests/shell/test-*.sh
