#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
image_script="${repo_root}/scripts/kubernetes-image.sh"
policy_script="${repo_root}/scripts/kubernetes-promotion-policy.sh"

homolog_digest="$(bash "${image_script}" get homologacao)"
production_ref="$(bash "${image_script}" ref producao)"
grep -Eq '^sha256:[0-9a-f]{64}$' <<<"${homolog_digest}"
grep -Eq '^[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/oficina-mecanica-api@sha256:[0-9a-f]{64}$' <<<"${production_ref}"

if bash "${image_script}" set homologacao 'not-an-ecr-repository' 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' >/dev/null 2>&1; then
  printf 'Repository inválido foi aceito.\n' >&2
  exit 1
fi
if bash "${image_script}" set homologacao '123456789012.dkr.ecr.us-east-1.amazonaws.com/oficina-mecanica-api' 'latest' >/dev/null 2>&1; then
  printf 'Tag latest foi aceita como digest.\n' >&2
  exit 1
fi
if bash "${policy_script}" homologacao feature/test README.md >/dev/null 2>&1; then
  printf 'Arquivo fora do overlay foi aceito.\n' >&2
  exit 1
fi
bash "${policy_script}" homologacao feature/base kubernetes/oficina-api/base/deployment.yaml >/dev/null

bash "${policy_script}" homologacao promote/test kubernetes/oficina-api/overlays/producao/kustomization.yaml >/dev/null
printf 'Kubernetes image policy checks passed.\n'
