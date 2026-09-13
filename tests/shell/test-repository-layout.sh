#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test "$(<"${repo_root}/.terraform-version")" = "1.16.1"
for stack in shared homologacao producao; do
  test -d "${repo_root}/environments/${stack}"
done
test -f "${repo_root}/kubernetes/oficina-api/base/kustomization.yaml"
test -f "${repo_root}/kubernetes/oficina-api/base/migration-job.yaml"
grep -Fq '*.tfstate' "${repo_root}/.gitignore"
grep -Fq '*.tfplan' "${repo_root}/.gitignore"
grep -Fq '/.github/workflows/' "${repo_root}/.github/CODEOWNERS"
