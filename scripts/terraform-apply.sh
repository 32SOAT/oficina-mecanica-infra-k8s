#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Source path is derived from BASH_SOURCE and unavailable to static analysis.
# shellcheck disable=SC1091
source "${script_dir}/lib/terraform-common.sh"

[[ $# -eq 2 ]] || die 'Uso: terraform-apply.sh <shared|homologacao|producao> <plan-file>'
stack="$(validate_stack "$1")"
plan_file="$2"
if [[ "${plan_file}" != /* ]]; then
  plan_file="$(pwd)/${plan_file}"
fi
[[ -f "${plan_file}" && ! -L "${plan_file}" ]] || die "Arquivo de plan regular ausente: ${plan_file}"
[[ -f "${plan_file}.stack" && ! -L "${plan_file}.stack" ]] || die "Marker de stack ausente: ${plan_file}.stack"
[[ "$(<"${plan_file}.stack")" == "${stack}" ]] || die 'Marker de stack não corresponde ao plan selecionado'

if [[ "${CI:-}" == 'true' ]]; then
  case "${stack}" in
    homologacao) expected_ref='refs/heads/homolog' ;;
    shared|producao) expected_ref='refs/heads/main' ;;
  esac
  [[ "${GITHUB_REF:-}" == "${expected_ref}" ]] || die "Branch não autorizada para ${stack}"
elif [[ "${TF_ALLOW_LOCAL_APPLY:-}" != '1' ]]; then
  die 'Apply local exige TF_ALLOW_LOCAL_APPLY=1'
fi

bash "${script_dir}/terraform-init.sh" "${stack}"
stack_dir="$(stack_directory "${stack}")"
require_command terraform
terraform -chdir="${stack_dir}" apply -input=false "${plan_file}"
