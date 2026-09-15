#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

for manifest_dir in base overlays/homologacao overlays/producao; do
  rendered="$(kubectl kustomize "${repo_root}/kubernetes/oficina-api/${manifest_dir}")"

  test "$(grep -Fc 'runAsNonRoot: true' <<<"${rendered}")" -ge 1
  test "$(grep -Fc 'runAsUser: 10001' <<<"${rendered}")" -ge 1
  test "$(grep -Fc 'allowPrivilegeEscalation: false' <<<"${rendered}")" -ge 1
  test "$(grep -Fc 'readOnlyRootFilesystem: true' <<<"${rendered}")" -ge 1
  test "$(grep -Fc -- '- ALL' <<<"${rendered}")" -ge 1
done

printf 'Kubernetes security context checks passed.\n'
