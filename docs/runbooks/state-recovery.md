# Recuperação do state Terraform

Use este procedimento somente para corrupção, exclusão ou regressão confirmada
do state remoto. O bucket é versionado e criptografado com KMS; restaure uma
versão existente no próprio S3, sem baixar ou imprimir o conteúdo do state.

## 1. Conter o incidente

1. Defina a variável de repositório `TF_DEPLOY_ENABLED=false` ou remova-a.
2. Cancele apenas jobs que ainda não começaram apply. Não cancele um apply em
   andamento; aguarde e avalie seu resultado.
3. Confirme que não há operação Terraform ativa para o stack.
4. Registre incidente, stack, commit, conta, região, bucket e state key.
5. Obtenha revisão de uma segunda pessoa antes de alterar a versão corrente.

Mapeamento fixo:

| Stack | S3 key |
| --- | --- |
| `shared` | `oficina/infra/shared/terraform.tfstate` |
| `homologacao` | `oficina/infra/homologacao/terraform.tfstate` |
| `producao` | `oficina/infra/producao/terraform.tfstate` |

## 2. Validar identidade e metadados

Use credenciais temporárias de recuperação e confirme a conta:

```bash
aws sts get-caller-identity --query Account --output text
aws s3api head-object \
  --bucket "${TF_BACKEND_BUCKET}" \
  --key 'oficina/infra/homologacao/terraform.tfstate' \
  --query '{VersionId:VersionId,LastModified:LastModified,Size:ContentLength}'
```

Não execute `get-object`, `terraform state pull` ou `terraform show` em terminal
gravado. O conteúdo do state não deve aparecer em logs, artifacts ou tickets.

Liste somente metadados das versões:

```bash
aws s3api list-object-versions \
  --bucket "${TF_BACKEND_BUCKET}" \
  --prefix 'oficina/infra/homologacao/terraform.tfstate' \
  --query 'Versions[].{VersionId:VersionId,IsLatest:IsLatest,LastModified:LastModified,Size:Size}'
```

Escolha uma versão com base no horário do incidente, commit aplicado e registros
do GitHub Actions. Guarde os IDs atual e candidato no registro do incidente.

## 3. Tratar lock órfão, se houver

O backend usa lockfile S3. Se houver um job ativo, não faça unlock. Se todos os
jobs terminaram e Terraform reporta um lock órfão, confira o Lock ID exato,
inicialize o root e peça confirmação da segunda pessoa:

```bash
bash scripts/terraform-init.sh homologacao
terraform -chdir=environments/homologacao force-unlock '<LOCK_ID_EXATO>'
```

Não exclua o `.tflock` diretamente e nunca use `-lock=false`.

## 4. Restaurar uma versão

Promova a versão escolhida para uma nova versão corrente com cópia server-side.
Isso preserva a versão danificada para auditoria e mantém o state criptografado:

```bash
state_key='oficina/infra/homologacao/terraform.tfstate'
restore_version='<VERSION_ID_VALIDADO>'

aws s3api copy-object \
  --bucket "${TF_BACKEND_BUCKET}" \
  --key "${state_key}" \
  --copy-source "${TF_BACKEND_BUCKET}/${state_key}?versionId=${restore_version}" \
  --server-side-encryption aws:kms \
  --ssekms-key-id "${TF_BACKEND_KMS_KEY_ID}" \
  --metadata-directive COPY
```

Registre o novo `VersionId` retornado. Não apague versões antigas.

## 5. Verificar sem aplicar

Inicialize novamente, audite somente metadados/endereços e gere um saved plan:

```bash
bash scripts/terraform-init.sh homologacao
bash scripts/terraform-state-audit.sh homologacao
plan_file="$(mktemp -t oficina-recovery.XXXXXX.tfplan)"
bash scripts/terraform-plan.sh homologacao "${plan_file}"
bash scripts/terraform-plan-policy.sh homologacao "${plan_file}"
```

Uma restauração antiga pode fazer Terraform propor recriação ou remoção de
recursos alterados depois daquela versão. Não aplique automaticamente. Reconcilie
recursos, imports e ownership por PR revisado. Para corrigir uma restauração
incorreta, repita a cópia server-side usando o `VersionId` que era corrente antes
do incidente.

Reative `TF_DEPLOY_ENABLED=true` somente após plan revisado, state consistente e
encerramento formal do incidente.
