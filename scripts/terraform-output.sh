#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Source path is derived from BASH_SOURCE and unavailable to static analysis.
# shellcheck disable=SC1091
source "${script_dir}/lib/terraform-common.sh"

[[ $# -eq 2 ]] || die 'Uso: terraform-output.sh <shared|homologacao|producao> <output-name>'
stack="$(validate_stack "$1")"
output_name="$2"

case "${output_name}" in
  repository_url|cluster_name|vpc_id|public_subnet_ids|private_subnet_ids|database_subnet_ids|database_client_security_group_id|publisher_role_arn|deployer_role_arn) ;;
  *) die "Output não permitido: ${output_name}" ;;
esac

bash "${script_dir}/terraform-init.sh" "${stack}"
stack_dir="$(stack_directory "${stack}")"
require_command terraform
terraform -chdir="${stack_dir}" output -json "${output_name}"
