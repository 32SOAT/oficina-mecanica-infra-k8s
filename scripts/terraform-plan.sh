#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Source path is derived from BASH_SOURCE and unavailable to static analysis.
# shellcheck disable=SC1091
source "${script_dir}/lib/terraform-common.sh"

[[ $# -eq 2 ]] || die 'Uso: terraform-plan.sh <shared|homologacao|producao> <plan-file>'
stack="$(validate_stack "$1")"
plan_file="$2"
[[ -n "${plan_file}" ]] || die 'Arquivo de plan ausente'

if [[ "${plan_file}" != /* ]]; then
  plan_file="$(pwd)/${plan_file}"
fi

# A stale marker must never authorize a plan that did not complete.
rm -f -- "${plan_file}.stack"
bash "${script_dir}/terraform-init.sh" "${stack}"
stack_dir="$(stack_directory "${stack}")"
require_command terraform

if terraform -chdir="${stack_dir}" plan \
  -input=false \
  -lock-timeout=5m \
  -detailed-exitcode \
  -out="${plan_file}"; then
  plan_exit_status=0
else
  plan_exit_status=$?
fi

case "${plan_exit_status}" in
  0|2)
    printf '%s\n' "${stack}" >"${plan_file}.stack"
    exit 0
    ;;
  *) exit "${plan_exit_status}" ;;
esac
