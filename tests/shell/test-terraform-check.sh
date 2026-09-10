#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT

# Exercise the real orchestrator, isolating only external Terraform/ShellCheck
# and the nested shell suite so this regression cannot recursively run itself.
mkdir -p "${test_dir}/scripts/lib" "${test_dir}/tests/shell" "${test_dir}/bin"
cp "${repo_root}/scripts/terraform-check.sh" "${test_dir}/scripts/"
cp "${repo_root}/scripts/lib/terraform-common.sh" "${test_dir}/scripts/lib/"
printf '#!/usr/bin/env bash\nexit 0\n' >"${test_dir}/tests/shell/test-nested.sh"
cat >"${test_dir}/bin/terraform" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\t' "$@" >>"${CHECK_CALL_LOG:?}"
printf '\n' >>"${CHECK_CALL_LOG}"
EOF
printf '#!/usr/bin/env bash\nexit 0\n' >"${test_dir}/bin/shellcheck"
chmod +x "${test_dir}/bin/terraform" "${test_dir}/bin/shellcheck"

roots=(
  bootstrap/backend bootstrap/identity
  modules/network modules/eks modules/ecr modules/platform-contract
  modules/api-publisher-identity modules/api-deployer-identity
  environments/shared environments/homologacao environments/producao
)
for root in "${roots[@]}"; do
  mkdir -p "${test_dir}/${root}"
done
export CHECK_CALL_LOG="${test_dir}/calls"
PATH="${test_dir}/bin:${PATH}" bash "${test_dir}/scripts/terraform-check.sh"

# Every real test root must be initialized without a backend, then validated
# and tested exactly once. Omitting any bootstrap/module must fail this test.
printf 'fmt\t-check\t-recursive\t\n' >"${test_dir}/expected"
for root in "${roots[@]}"; do
  {
    printf '%s\tinit\t-backend=false\t-input=false\t-lockfile=readonly\t\n' "-chdir=${test_dir}/${root}"
    printf '%s\tvalidate\t\n' "-chdir=${test_dir}/${root}"
    printf '%s\ttest\t\n' "-chdir=${test_dir}/${root}"
  } >>"${test_dir}/expected"
done
diff -u "${test_dir}/expected" "${CHECK_CALL_LOG}"
printf 'Terraform complete-root checks passed.\n'
