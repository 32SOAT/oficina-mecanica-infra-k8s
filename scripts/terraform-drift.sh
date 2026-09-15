#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Source path is derived from BASH_SOURCE and unavailable to static analysis.
# shellcheck disable=SC1091
source "${script_dir}/lib/terraform-common.sh"

[[ $# -eq 1 ]] || die 'Uso: terraform-drift.sh <shared|homologacao|producao>'
stack="$(validate_stack "$1")"

bash "${script_dir}/terraform-init.sh" "${stack}"
stack_dir="$(stack_directory "${stack}")"
require_command terraform

if terraform -chdir="${stack_dir}" plan \
  -input=false \
  -lock-timeout=5m \
  -refresh-only \
  -detailed-exitcode; then
  drift_exit_status=0
else
  drift_exit_status=$?
fi

case "${drift_exit_status}" in
  0|2) exit "${drift_exit_status}" ;;
  *) exit 1 ;;
esac
