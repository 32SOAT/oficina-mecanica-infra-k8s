#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

die() {
  printf 'Erro: %s\n' "$1" >&2
  exit 1
}

[[ $# -ge 2 ]] || die 'Uso: kubernetes-promotion-policy.sh <base-ref> <head-ref> <paths...>'
base_ref="$1"
head_ref="$2"
shift 2
[[ $# -gt 0 ]] || die 'Nenhum arquivo alterado foi informado.'

for path in "$@"; do
  [[ "${path}" == kubernetes/oficina-api/overlays/homologacao/kustomization.yaml ||
    "${path}" == kubernetes/oficina-api/overlays/producao/kustomization.yaml ]] ||
    die "Arquivo fora do escopo de promoção: ${path}"
done

if [[ "${base_ref}" == "main" || "${head_ref}" == "main" || "${head_ref}" == promote/* ]]; then
  [[ "$#" -eq 1 && "$1" == kubernetes/oficina-api/overlays/producao/kustomization.yaml ]] ||
    die 'Promoção para produção deve alterar somente o overlay de produção.'
  production_digest="$(bash "${script_dir}/kubernetes-image.sh" get producao)"
  homolog_digest="$(bash "${script_dir}/kubernetes-image.sh" get homologacao)"
  [[ "${production_digest}" == "${homolog_digest}" ]] || die 'Digest de produção deve coincidir com homologação.'
fi

printf 'Kubernetes promotion policy passed.\n'
