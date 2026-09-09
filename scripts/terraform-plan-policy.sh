#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Source path is derived from BASH_SOURCE and unavailable to static analysis.
# shellcheck disable=SC1091
source "${script_dir}/lib/terraform-common.sh"

[[ $# -eq 2 ]] || die 'Uso: terraform-plan-policy.sh <shared|homologacao|producao> <plan-file>'
stack="$(validate_stack "$1")"
plan_file="$2"
[[ -f "${plan_file}" ]] || die "Arquivo de plan ausente: ${plan_file}"
require_command jq

plan_json() {
  if jq -e . "${plan_file}" >/dev/null 2>&1; then
    cat -- "${plan_file}"
  else
    require_command terraform
    terraform show -json "${plan_file}"
  fi
}

if [[ "${stack}" == 'producao' ]]; then
  if ! plan_json | jq -e '
    def actions: .change.actions // [];
    def unsafe_eks_endpoint:
      .resource_changes[]?
      | select(.type == "aws_eks_cluster")
      | .change.after.vpc_config?
      | ..
      | strings
      | select(. == "0.0.0.0/0");

    (.resource_changes | type == "array")
    and ([.resource_changes[]? | select(actions | index("delete") != null)] | length == 0)
    and ([unsafe_eks_endpoint] | length == 0)
  ' >/dev/null; then
    die 'Política de plan recusou mudança destrutiva ou endpoint EKS público'
  fi
else
  plan_json | jq -e '.resource_changes | type == "array"' >/dev/null || die 'JSON do plan inválido'
fi
