# Publicação da imagem e deploy por digest

**Projeto:** Oficina Mecânica  
**Repositórios:** `oficina-mecanica-api` e `oficina-mecanica-infra-k8s`

## Objetivo

Este documento é o procedimento operacional do fluxo implementado: a API
publica a imagem, o infra-k8s versiona o digest e o workflow Kubernetes executa
migration, rollout e health check. As fases abaixo também servem como checklist
de revisão quando o fluxo for alterado.

Separar a publicação da imagem Docker do deploy no EKS:

1. `oficina-mecanica-api` valida o código e publica manualmente uma imagem imutável no ECR.
2. `oficina-mecanica-infra-k8s` versiona o digest, executa migrations e faz o deploy após o merge de um Pull Request.

O workflow da API não executará `kubectl`, Terraform ou deploy. O workflow de deploy não fará build nem push da imagem.

## Fluxo final

```text
PR da API
  -> build, testes e Docker build sem push

workflow_dispatch na API
  -> seleciona commit de homolog/main
  -> build/test
  -> OIDC para role de publicação
  -> push ECR com sha-<SHA completo>
  -> retorna sha256:<digest>

PR na infraestrutura
  -> altera o digest do overlay
  -> valida Kustomize, schema e política

merge em homolog/main
  -> OIDC para role de deploy
  -> valida digest
  -> migration
  -> rollout e health check
```

Não haverá atualização automática entre os repositórios na primeira versão. O digest será copiado do resumo da publicação e revisado no PR da infraestrutura.

## Regras de segurança

- Usar somente tags `sha-<40 caracteres>` durante a publicação.
- Usar `repository@sha256:<64 hexadecimais>` nos manifests.
- Nunca publicar ou promover `latest`.
- Aceitar no publicador apenas commits alcançáveis por `homolog` ou `main`.
- Usar GitHub OIDC; não armazenar access keys permanentes.
- Guardar banco, JWT e Resend nos GitHub Environments.
- A role de publicação deve acessar apenas ECR e o parâmetro SSM do repositório.
- A role de deploy deve ser limitada ao cluster, SSM e namespace da aplicação.
- Produção deve usar exatamente o digest aprovado em homologação.

## Fase 1 — Publicador da API

No `oficina-mecanica-api`, criar ou ajustar:

```text
infra/publish-api-image.sh
test/scripts/test-publish-api-image.sh
```

Entradas do script:

```text
SOURCE_SHA
AWS_REGION
ECR_REPOSITORY_URL
API_IMAGE_PLATFORM
```

Saídas:

```text
IMAGE_TAG=sha-<SHA completo>
IMAGE_DIGEST=sha256:<digest>
IMAGE_REF=<repository>@<digest>
```

O script deve validar o SHA, autenticar no ECR, executar `docker buildx build --push`, consultar `aws ecr describe-images` e validar o digest retornado. Testar SHA curto, URL inválida, plataforma inválida, digest inválido e tentativa de usar `latest`.

## Fase 2 — Workflows da API

Criar:

```text
.github/workflows/ci.yml
.github/workflows/publish-image.yml
```

O `ci.yml` executará em Pull Requests para `homolog` e `main`:

- `npm ci`;
- build;
- testes com cobertura;
- Docker build sem push;
- check obrigatório `api / gate`.

O `publish-image.yml` usará somente `workflow_dispatch`, com input `git_ref`, environment `image-publishing`, OIDC e leitura do ECR pelo contrato SSM `/oficina/shared/ecr/repository-url`.

Depois de validar os novos workflows, remover o workflow misto atual que combina build, push e deploy.

## Fase 3 — Manifests na infraestrutura

No `oficina-mecanica-infra-k8s`, criar:

```text
kubernetes/platform/namespace.yaml
kubernetes/oficina-api/base/
kubernetes/oficina-api/overlays/homologacao/
kubernetes/oficina-api/overlays/producao/
```

A base conterá Deployment, Service, HPA e Job de migration, sem secrets e sem Namespace. O namespace será criado uma vez por identidade administrativa.

Cada overlay deverá declarar a imagem por digest:

```yaml
images:
  - name: oficina-mecanica-api
    newName: 123456789012.dkr.ecr.us-east-1.amazonaws.com/oficina-mecanica-api
    digest: sha256:...
```

## Fase 4 — Validação e promoção

Criar:

```text
scripts/kubernetes-image.sh
scripts/kubernetes-validate.sh
scripts/kubernetes-promotion-policy.sh
tests/kubernetes/test-image-policy.sh
```

Os helpers devem rejeitar tags, `latest`, digest inválido, alterações fora do overlay e produção com digest diferente de homologação.

Comandos previstos:

```bash
bash scripts/kubernetes-image.sh get homologacao
bash scripts/kubernetes-image.sh ref homologacao
bash scripts/kubernetes-image.sh set homologacao "$ECR_REPOSITORY_URL" "$IMAGE_DIGEST"
```

## Fase 5 — Deploy seguro

Criar `scripts/kubernetes-deploy.sh` e seus testes. A sequência obrigatória será:

1. validar o digest no ECR;
2. criar ConfigMap e Secret de forma efêmera;
3. aplicar o Job de migration;
4. aguardar a migration concluir;
5. abortar se a migration falhar;
6. aplicar o overlay da aplicação;
7. aguardar o rollout;
8. executar health check HTTP.

Nenhum secret pode aparecer em logs, artifacts ou arquivos versionados.

## Fase 6 — Workflows da infraestrutura

Criar:

```text
.github/workflows/kubernetes-ci.yml
.github/workflows/kubernetes-deploy.yml
```

O `kubernetes-ci.yml` deverá publicar sempre o check `kubernetes / gate`, validar Kustomize, kubeconform e a política de promoção.

O `kubernetes-deploy.yml` deverá mapear:

```text
homolog -> homologacao
main    -> producao
```

Deverá usar OIDC, role por ambiente, concorrência por ambiente e flags explícitas de habilitação. Não deverá aceitar imagem como input.

## Fase 7 — GitHub Environments

### API: `image-publishing`

Configurar a role OIDC de publicação, vinculada ao repositório e ao environment.

### Infraestrutura: `homologacao` e `producao`

Variables:

```text
AWS_REGION
AWS_ACCOUNT_ID
DEPLOY_ROLE_ARN
EKS_CLUSTER_NAME
ECR_REPOSITORY_URL (opcional; sem ela o deploy lê o contrato SSM)
K8S_NAMESPACE (deve permanecer oficina-mecanica)
POSTGRES_HOST
POSTGRES_PORT
POSTGRES_DB
POSTGRES_USER
POSTGRES_SYNC
POSTGRES_SSL
POSTGRES_SSL_REJECT_UNAUTHORIZED
JWT_EXPIRES_IN
NOTIFICACAO_EMAIL_MECANICOS
NOTIFICACAO_EMAIL_ADMIN
```

Secrets:

```text
POSTGRES_PASSWORD
JWT_SECRET
RESEND_API_KEY
```

Restringir `homologacao` à branch `homolog` e `producao` à branch `main`. Habilitar homologação primeiro; manter produção desabilitada até o cutover.

As variáveis `KUBERNETES_HOMOLOGACAO_DEPLOY_ENABLED` e
`KUBERNETES_PRODUCAO_DEPLOY_ENABLED` são variáveis de repositório usadas como
travas explícitas pelo workflow. O cluster e o ECR devem corresponder à mesma
conta/região do environment; o script rejeita namespaces diferentes de
`oficina-mecanica` e repositórios que não sejam o ECR da API.

## Operação

### Publicar imagem

1. Fazer merge da API em `homolog`.
2. Executar `publish-image.yml` manualmente.
3. Informar o SHA completo.
4. Copiar `IMAGE_DIGEST` e `IMAGE_REF`.

### Promover para homologação

1. Atualizar o overlay de homologação com o digest.
2. Abrir PR para `homolog` no repositório de infraestrutura.
3. Aguardar `terraform / gate` e `kubernetes / gate`.
4. Fazer merge e acompanhar migration, rollout e health check.

### Promover para produção

1. Confirmar que o digest está em homologação.
2. Criar `promote/<identificador>`.
3. Alterar somente o overlay de produção.
4. Abrir PR para `main`.
5. Validar digest idêntico ao de homologação.
6. Fazer merge após aprovação.

### Rollback

Restaurar o digest anterior por um novo PR. Não reconstruir a imagem e não usar `latest`.

## Branches

```text
API:  feat/manual-ecr-publish -> main
Infra: feat/kubernetes-image-promotion -> homolog
       promote/<release> -> main
```

## Critérios de aceite

- PR da API valida código e Docker sem publicar.
- Publicação manual gera tag e digest imutáveis.
- Publicação não executa deploy.
- PR de infraestrutura altera somente o digest permitido.
- CI rejeita tags, `latest` e digest inválido.
- Migration falha antes do Deployment quando houver erro.
- Rollout e health check são verificados.
- Produção usa exatamente o digest homologado.
- Nenhum secret é versionado ou exposto.

## Ordem de implementação

1. Script de publicação e testes na API.
2. `ci.yml` e `publish-image.yml`.
3. Remoção do workflow misto.
4. Migração dos manifests.
5. Overlays e política de digest.
6. Script de deploy com migration.
7. Workflows Kubernetes.
8. Roles OIDC e GitHub Environments.
9. Primeiro cutover em homologação.
10. Promoção controlada para produção.
