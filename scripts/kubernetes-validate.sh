#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
environment="${1:-}"
case "${environment}" in
  homologacao|producao) ;;
  *) printf 'Uso: kubernetes-validate.sh <homologacao|producao>\n' >&2; exit 1 ;;
esac

command -v kubectl >/dev/null 2>&1 || { printf 'kubectl ausente.\n' >&2; exit 1; }
overlay="${repo_root}/kubernetes/oficina-api/overlays/${environment}"
rendered="$(kubectl kustomize "${overlay}")"
grep -Eq 'image: [^[:space:]]+@sha256:[0-9a-f]{64}' <<<"${rendered}" || {
  printf 'Overlay %s não resolve a imagem por digest.\n' "${environment}" >&2
  exit 1
}
if grep -Eq 'newTag:|:latest([[:space:]]|$)' <<<"${rendered}"; then
  printf 'Overlay %s contém tag mutável.\n' "${environment}" >&2
  exit 1
fi
grep -Fq 'apiVersion: batch/v1' "${repo_root}/kubernetes/oficina-api/base/migration-job.yaml"
grep -Fq 'migration:run' "${repo_root}/kubernetes/oficina-api/base/migration-job.yaml"
printf 'Kubernetes overlay %s validated.\n' "${environment}"
