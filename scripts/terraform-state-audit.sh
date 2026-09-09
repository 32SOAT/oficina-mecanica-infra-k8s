#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Source path is derived from BASH_SOURCE and unavailable to static analysis.
# shellcheck disable=SC1091
source "${script_dir}/lib/terraform-common.sh"

[[ $# -eq 1 ]] || die 'Uso: terraform-state-audit.sh <shared|homologacao|producao>'
stack="$(validate_stack "$1")"

bash "${script_dir}/terraform-init.sh" "${stack}"
stack_dir="$(stack_directory "${stack}")"
require_command terraform

printf 'Stack: %s\n' "${stack}"
printf 'Endereços do state:\n'
terraform -chdir="${stack_dir}" state list
printf 'Providers:\n'
terraform -chdir="${stack_dir}" providers
