#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "${test_dir}"' EXIT
mkdir -p "${test_dir}/bin"

cat >"${test_dir}/bin/aws" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'aws %s\n' "$*" >>"${FAKE_LOG}"
if [[ "$*" == *'ssm get-parameter'* ]]; then
  printf '%s\n' "${ECR_REPOSITORY_URL}"
elif [[ "$*" == *'ecr describe-images'* ]]; then
  printf '%s\n' 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
fi
EOF

cat >"${test_dir}/bin/kubectl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'kubectl %s\n' "$*" >>"${FAKE_LOG}"
if [[ "$*" == *' create '* || "$*" == create\ * ]]; then
  printf '%s\n' 'apiVersion: v1' 'kind: ConfigMap'
elif [[ "$*" == *' get service '* ]]; then
  printf '%s\n' 'api.example.test'
elif [[ "$*" == *' wait '* && "${FAKE_MIGRATION_FAIL:-0}" == 1 ]]; then
  exit 1
fi
EOF

cat >"${test_dir}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
printf 'curl %s\n' "$*" >>"${FAKE_LOG}"
EOF
chmod +x "${test_dir}/bin/aws" "${test_dir}/bin/kubectl" "${test_dir}/bin/curl"

export PATH="${test_dir}/bin:${PATH}"
export FAKE_LOG="${test_dir}/commands.log"
export AWS_REGION=us-east-1
export CLUSTER_NAME=oficina-mecanica-homologacao
export ECR_REPOSITORY_URL=123456789012.dkr.ecr.us-east-1.amazonaws.com/oficina-mecanica-api
export POSTGRES_HOST=db.example.test POSTGRES_PORT=5432 POSTGRES_DB=oficina_mecanica POSTGRES_USER=oficina
export POSTGRES_PASSWORD=not-printed POSTGRES_SYNC=0 POSTGRES_SSL=1 POSTGRES_SSL_REJECT_UNAUTHORIZED=0
export JWT_SECRET=not-printed JWT_EXPIRES_IN=1h RESEND_API_KEY=not-printed
export NOTIFICACAO_EMAIL_MECANICOS=mechanics@example.test NOTIFICACAO_EMAIL_ADMIN=admin@example.test

bash "${repo_root}/scripts/kubernetes-deploy.sh" homologacao
grep -n 'kubectl apply -f' "${FAKE_LOG}"
grep -n 'kubectl apply -k' "${FAKE_LOG}"
grep -n ' rollout status ' "${FAKE_LOG}"
grep -n 'curl --fail' "${FAKE_LOG}"
apply_workload_line="$(grep -n 'kubectl apply -k' "${FAKE_LOG}" | cut -d: -f1)"
rollout_line="$(grep -n ' rollout status ' "${FAKE_LOG}" | cut -d: -f1)"
(( apply_workload_line < rollout_line ))

if KUBERNETES_NAMESPACE=outro bash "${repo_root}/scripts/kubernetes-deploy.sh" homologacao >/dev/null 2>&1; then
  printf 'Namespace fora do contrato foi aceito.\n' >&2
  exit 1
fi

: >"${FAKE_LOG}"
export FAKE_MIGRATION_FAIL=1
if bash "${repo_root}/scripts/kubernetes-deploy.sh" homologacao >/dev/null 2>&1; then
  printf 'Falha de migration foi ignorada.\n' >&2
  exit 1
fi
if grep -Fq 'kubectl apply -k' "${FAKE_LOG}"; then
  printf 'Workload aplicado depois de migration malsucedida.\n' >&2
  exit 1
fi

printf 'Kubernetes deploy checks passed.\n'
