#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
overlay_root="${repo_root}/kubernetes/oficina-api/overlays"

die() {
  printf 'Erro: %s\n' "$1" >&2
  exit 1
}

usage() {
  die 'Uso: kubernetes-image.sh {get|ref|set} <homologacao|producao> [repository-url digest]'
}

command_name="${1:-}"
environment="${2:-}"
case "${command_name}" in get|ref|set) ;; *) usage ;; esac
case "${environment}" in homologacao|producao) ;; *) die 'Ambiente inválido.' ;; esac

overlay_file="${overlay_root}/${environment}/kustomization.yaml"
[[ -f "${overlay_file}" ]] || die "Overlay ausente: ${overlay_file}"

read_image_values() {
  local image_name image_digest
  image_name="$(sed -n 's/^    newName: //p' "${overlay_file}" | head -n 1)"
  image_digest="$(sed -n 's/^    digest: //p' "${overlay_file}" | head -n 1)"
  [[ "${image_name}" =~ ^[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/oficina-mecanica-api$ ]] || die 'newName não é um repositório ECR válido.'
  [[ "${image_digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || die 'digest do overlay é inválido.'
  printf '%s\n%s\n' "${image_name}" "${image_digest}"
}

case "${command_name}" in
  get)
    read_image_values | tail -n 1
    ;;
  ref)
    values="$(read_image_values)"
    image_name="$(head -n 1 <<<"${values}")"
    image_digest="$(tail -n 1 <<<"${values}")"
    printf '%s@%s\n' "${image_name}" "${image_digest}"
    ;;
  set)
    [[ $# -eq 4 ]] || usage
    repository_url="${3}"
    digest="${4}"
    [[ "${repository_url}" =~ ^[0-9]{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/oficina-mecanica-api$ ]] || die 'repository-url deve ser o ECR da API.'
    [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || die 'digest deve ter o formato sha256:<64 hexadecimais>.'
    temporary_file="$(mktemp "${overlay_file}.XXXXXX")"
    trap 'rm -f -- "${temporary_file}"' EXIT
    printf '%s\n' \
      'apiVersion: kustomize.config.k8s.io/v1beta1' \
      'kind: Kustomization' \
      'namespace: oficina-mecanica' \
      'resources:' \
      '  - ../../base' \
      'images:' \
      '  - name: oficina-mecanica-api' \
      "    newName: ${repository_url}" \
      "    digest: ${digest}" >"${temporary_file}"
    mv -- "${temporary_file}" "${overlay_file}"
    trap - EXIT
    printf '%s@%s\n' "${repository_url}" "${digest}"
    ;;
esac
