#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_bin="$(mktemp -d)"
cleanup() {
  local status=$?
  rm -rf "${test_bin}"
  exit "${status}"
}
trap cleanup EXIT

cat >"${test_bin}/aws" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "${FAKE_AWS_ACCOUNT_ID:?}"
EOF
chmod +x "${test_bin}/aws"

cat >"${test_bin}/terraform" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
test "$1" = "-chdir=${EXPECTED_STACK_DIRECTORY:?}"
test "$2" = 'workspace'
test "$3" = 'show'
exit "${FAKE_TERRAFORM_EXIT_STATUS:-0}"
EOF
chmod +x "${test_bin}/terraform"

PATH="${test_bin}:${PATH}"
export PATH
cd "${test_bin}"

# A wrong allowlist branch, a wrong state key, or an uninitialized-backend
# failure that is ignored must make this test fail.
test -f "${repo_root}/scripts/lib/terraform-common.sh"
# Source path is derived from BASH_SOURCE and unavailable to static analysis.
# shellcheck disable=SC1091
source "${repo_root}/scripts/lib/terraform-common.sh"

test "$(validate_stack shared)" = 'shared'
test "$(validate_stack homologacao)" = 'homologacao'
test "$(validate_stack producao)" = 'producao'
if (validate_stack dev >/dev/null 2>&1); then
  exit 1
fi
test "$(state_key homologacao)" = 'oficina/infra/homologacao/terraform.tfstate'
for invalid_stack in dev '' ../shared; do
  for helper in state_key stack_directory assert_initialized_backend; do
    if ("${helper}" "${invalid_stack}" >/dev/null 2>&1); then
      printf 'FAIL: %s aceitou stack inválido: %s\n' "${helper}" "${invalid_stack}" >&2
      exit 1
    fi
  done
done
test "$(stack_directory producao)" = "${repo_root}/environments/producao"
require_command bash
if (require_command command-that-does-not-exist >/dev/null 2>&1); then
  exit 1
fi

FAKE_AWS_ACCOUNT_ID='123456789012'
export FAKE_AWS_ACCOUNT_ID
assert_aws_identity '123456789012'
if (assert_aws_identity '210987654321' >/dev/null 2>&1); then
  exit 1
fi

EXPECTED_STACK_DIRECTORY="${repo_root}/environments/shared"
export EXPECTED_STACK_DIRECTORY
TF_DATA_DIR="${test_bin}/terraform-data"
export TF_DATA_DIR
mkdir -p "${TF_DATA_DIR}"
if (assert_initialized_backend shared >/dev/null 2>&1); then
  printf 'FAIL: backend ausente foi aceito\n' >&2
  exit 1
fi
printf '%s\n' '{"backend":{"type":"s3","config":{"key":"oficina/infra/shared/terraform.tfstate"}}}' >"${TF_DATA_DIR}/terraform.tfstate"
assert_initialized_backend shared
printf '%s\n' '{"backend":{"type":"s3","config":{"key":"oficina/infra/producao/terraform.tfstate"}}}' >"${TF_DATA_DIR}/terraform.tfstate"
if (assert_initialized_backend shared >/dev/null 2>&1); then
  printf 'FAIL: backend de outro stack foi aceito\n' >&2
  exit 1
fi
printf '%s\n' '{"backend":{"type":"s3","config":{"key":"oficina/infra/shared/terraform.tfstate"}}}' >"${TF_DATA_DIR}/terraform.tfstate"
FAKE_TERRAFORM_EXIT_STATUS=1
export FAKE_TERRAFORM_EXIT_STATUS
if (assert_initialized_backend shared >"${test_bin}/backend-output" 2>&1); then
  exit 1
fi
grep -Fxq 'Erro: Backend Terraform não inicializado: shared' "${test_bin}/backend-output"
