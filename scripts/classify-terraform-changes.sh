#!/usr/bin/env bash
set -Eeuo pipefail

terraform_changed=false
shared_changed=false
environment_changed=false

while IFS= read -r changed_path || [[ -n "${changed_path}" ]]; do
  [[ -n "${changed_path}" ]] || continue

  if [[ "${changed_path}" =~ ^(environments/|modules/|bootstrap/|scripts/(terraform-[^/]+|classify-terraform-changes)\.sh$|scripts/lib/terraform-common\.sh$|\.github/workflows/terraform-[^/]+\.yml$|\.terraform-version$) ]]; then
    terraform_changed=true
  fi

  if [[ "${changed_path}" =~ ^(environments/shared/|modules/(ecr|api-publisher-identity|platform-contract)/|bootstrap/|scripts/(terraform-[^/]+|classify-terraform-changes)\.sh$|scripts/lib/terraform-common\.sh$|\.github/workflows/terraform-[^/]+\.yml$|\.terraform-version$) ]]; then
    shared_changed=true
  fi

  if [[ "${changed_path}" =~ ^(environments/(homologacao|producao)/|modules/(network|eks|api-deployer-identity|platform-contract)/|bootstrap/|scripts/(terraform-[^/]+|classify-terraform-changes)\.sh$|scripts/lib/terraform-common\.sh$|\.github/workflows/terraform-[^/]+\.yml$|\.terraform-version$) ]]; then
    environment_changed=true
  fi
done

printf 'terraform_changed=%s\n' "${terraform_changed}"
printf 'shared_changed=%s\n' "${shared_changed}"
printf 'environment_changed=%s\n' "${environment_changed}"
