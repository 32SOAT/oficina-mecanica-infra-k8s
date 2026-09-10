#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
environment="${1:-}"
case "${environment}" in
  homologacao|producao) ;;
  *) printf 'Uso: kubernetes-deploy.sh <homologacao|producao>\n' >&2; exit 1 ;;
esac

die() {
  printf 'Erro: %s\n' "$1" >&2
  exit 1
}

for command_name in aws kubectl curl; do
  command -v "${command_name}" >/dev/null 2>&1 || die "Comando ausente: ${command_name}"
done

required_variables=(
  AWS_REGION POSTGRES_HOST POSTGRES_PORT POSTGRES_DB POSTGRES_USER
  POSTGRES_PASSWORD POSTGRES_SYNC POSTGRES_SSL POSTGRES_SSL_REJECT_UNAUTHORIZED
  JWT_SECRET JWT_EXPIRES_IN RESEND_API_KEY NOTIFICACAO_EMAIL_MECANICOS
  NOTIFICACAO_EMAIL_ADMIN
)
for variable_name in "${required_variables[@]}"; do
  [[ -n "${!variable_name:-}" ]] || die "Variável ausente: ${variable_name}"
done

cluster_name="${CLUSTER_NAME:-}"
[[ -n "${cluster_name}" ]] || die 'CLUSTER_NAME deve estar definido.'
namespace="${KUBERNETES_NAMESPACE:-oficina-mecanica}"
api_name="fase2-kubernetes-oficina-mecanica-api"
overlay="${repo_root}/kubernetes/oficina-api/overlays/${environment}"
base_job="${repo_root}/kubernetes/oficina-api/base/migration-job.yaml"

ecr_repository_url="${ECR_REPOSITORY_URL:-}"
if [[ -z "${ecr_repository_url}" ]]; then
  ecr_repository_url="$(aws ssm get-parameter \
    --name /oficina/shared/ecr/repository-url \
    --with-decryption false \
    --query 'Parameter.Value' \
    --output text)"
fi
[[ "${ecr_repository_url}" =~ ^[0-9]{12}\.dkr\.ecr\.${AWS_REGION}\.amazonaws\.com/oficina-mecanica-api$ ]] || die 'ECR_REPOSITORY_URL não corresponde ao repositório esperado.'

image_reference="$(bash "${script_dir}/kubernetes-image.sh" ref "${environment}")"
[[ "${image_reference}" == "${ecr_repository_url}@sha256:"* ]] || die 'O overlay referencia um registry diferente do contrato ECR.'
repository_name="${ecr_repository_url##*/}"
image_digest="${image_reference##*@}"
[[ "${image_digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || die 'Digest do overlay é inválido.'

aws ecr describe-images \
  --region "${AWS_REGION}" \
  --repository-name "${repository_name}" \
  --image-ids "imageDigest=${image_digest}" \
  --query 'imageDetails[0].imageDigest' \
  --output text >/dev/null || die 'Digest não encontrado no ECR.'
runtime_dir="$(mktemp -d)"
umask 077
trap 'rm -rf -- "${runtime_dir}"' EXIT
config_file="${runtime_dir}/config.env"
secret_file="${runtime_dir}/secret.env"

cat >"${config_file}" <<EOF
NODE_ENV=production
APP_PORT=3000
POSTGRES_HOST=${POSTGRES_HOST}
POSTGRES_PORT=${POSTGRES_PORT}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_SYNC=${POSTGRES_SYNC}
POSTGRES_SSL=${POSTGRES_SSL}
POSTGRES_SSL_REJECT_UNAUTHORIZED=${POSTGRES_SSL_REJECT_UNAUTHORIZED}
JWT_EXPIRES_IN=${JWT_EXPIRES_IN}
NOTIFICACAO_EMAIL_MECANICOS=${NOTIFICACAO_EMAIL_MECANICOS}
NOTIFICACAO_EMAIL_ADMIN=${NOTIFICACAO_EMAIL_ADMIN}
EOF
cat >"${secret_file}" <<EOF
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
JWT_SECRET=${JWT_SECRET}
RESEND_API_KEY=${RESEND_API_KEY}
EOF
chmod 600 "${config_file}" "${secret_file}"

kubectl -n "${namespace}" create configmap "${api_name}-config" \
  --from-env-file="${config_file}" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "${namespace}" create secret generic "${api_name}-secret" \
  --from-env-file="${secret_file}" --dry-run=client -o yaml | kubectl apply -f -

sed "s|^          image: .*|          image: ${image_reference}|" "${base_job}" >"${runtime_dir}/migration-job.yaml"
kubectl -n "${namespace}" delete job "${api_name}-migrations" --ignore-not-found
kubectl apply -f "${runtime_dir}/migration-job.yaml"
if ! kubectl -n "${namespace}" wait \
  --for=condition=complete \
  "job/${api_name}-migrations" \
  --timeout=300s; then
  kubectl -n "${namespace}" describe job "${api_name}-migrations" >&2 || true
  kubectl -n "${namespace}" logs "job/${api_name}-migrations" --all-containers=true >&2 || true
  die 'Migration não concluiu; workload não será atualizado.'
fi

kubectl apply -k "${overlay}"
kubectl -n "${namespace}" rollout status \
  "deployment/${api_name}" --timeout=5m

service_host="$(kubectl -n "${namespace}" get service "${api_name}" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
[[ -n "${service_host}" ]] || die 'Service ainda não possui hostname do Load Balancer.'
for _ in $(seq 1 30); do
  if curl --fail --silent --show-error "http://${service_host}/api/v1/health" >/dev/null; then
    printf 'Kubernetes deploy %s concluído: %s@%s\n' "${environment}" "${repository_name}" "${image_digest}"
    exit 0
  fi
  sleep 10
done
die 'Smoke test da API falhou.'
