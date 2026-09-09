#!/usr/bin/env bash
set -Eeuo pipefail

terraform_common_repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

die() {
  printf 'Erro: %s\n' "$*" >&2
  exit 1
}

require_command() {
  local command_name="${1:-}"

  [[ -n "${command_name}" ]] || die 'Nome do comando ausente'
  command -v "${command_name}" >/dev/null 2>&1 || die "Comando obrigatório ausente: ${command_name}"
}

validate_stack() {
  case "${1:-}" in
    shared|homologacao|producao) printf '%s\n' "$1" ;;
    *) die "Stack inválido: ${1:-ausente}" ;;
  esac
}

stack_directory() {
  local stack
  stack="$(validate_stack "${1:-}")" || return 1

  local directory="${terraform_common_repo_root}/environments/${stack}"
  [[ -d "${directory}" ]] || die "Diretório do stack ausente: ${stack}"
  printf '%s\n' "${directory}"
}

state_key() {
  local stack
  stack="$(validate_stack "${1:-}")" || return 1
  printf 'oficina/infra/%s/terraform.tfstate\n' "${stack}"
}

assert_aws_identity() {
  local expected="${1:-}"
  local actual

  [[ -n "${expected}" ]] || die 'Conta AWS esperada ausente'
  require_command aws
  actual="$(aws sts get-caller-identity --query Account --output text)"
  [[ "${actual}" == "${expected}" ]] || die "Conta AWS inesperada: ${actual}"
}

assert_initialized_backend() {
  local directory data_directory backend_metadata
  directory="$(stack_directory "${1:-}")" || return 1

  data_directory="${TF_DATA_DIR:-.terraform}"
  if [[ "${data_directory}" != /* ]]; then
    data_directory="${directory}/${data_directory}"
  fi
  backend_metadata="${data_directory}/terraform.tfstate"

  require_command jq
  # This is Terraform's local backend metadata, never the remote resource state.
  # Suppress parser output because backend configuration may contain credentials.
  if [[ ! -f "${backend_metadata}" ]] ||
    ! jq -e --arg key "$(state_key "${1:-}")" \
      '.backend.type == "s3" and .backend.config.key == $key' \
      "${backend_metadata}" >/dev/null 2>&1; then
    die "Backend Terraform não inicializado: ${1:-ausente}"
  fi

  require_command terraform
  terraform -chdir="${directory}" workspace show >/dev/null 2>&1 || die "Backend Terraform não inicializado: ${1:-ausente}"
}
