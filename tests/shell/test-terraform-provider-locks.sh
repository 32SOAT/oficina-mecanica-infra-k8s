#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
linux_provider_hash='h1:PI0OJEVbr2Zdclvsrxshq6bCaxK0tTIj/gp93uhg26I='
alternate_linux_provider_hash='h1:edXOJWE4ORX8Fm+dpVpICzMZJat4AX0VRCAy/xkcOc0='

while IFS= read -r lockfile; do
  grep -Fq "\"${linux_provider_hash}\"" "${repo_root}/${lockfile}" || {
    printf 'Checksum linux_amd64 ausente em %s.\n' "${lockfile}" >&2
    exit 1
  }
  grep -Fq "\"${alternate_linux_provider_hash}\"" "${repo_root}/${lockfile}" || {
    printf 'Checksum alternativo do provider ausente em %s.\n' "${lockfile}" >&2
    exit 1
  }
done < <(cd "${repo_root}" && rg --files -g '.terraform.lock.hcl')

printf 'Terraform provider lock checks passed.\n'
