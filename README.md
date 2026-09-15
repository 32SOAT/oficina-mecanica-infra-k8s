# Oficina Mecânica Infra K8s

Repositório da plataforma Terraform e dos manifests Kubernetes da Oficina Mecânica.

## Ownership

| Responsável | Ownership |
| --- | --- |
| Plataforma (`oficina-mecanica-infra-k8s`) | Rede, EKS, provisionamento do ECR, IAM/OIDC, add-ons, manifests, promoção e deploy da API |
| Repositório de banco gerenciado | RDS, DB subnet group, security group do banco, backups, parâmetros e credenciais |
| `oficina-mecanica-api` | Aplicação, migrations TypeORM e build/publicação manual da imagem no ECR |

Nenhum recurso é gerenciado por mais de um state. Os únicos arquivos `tfvars`
versionáveis são `environments/shared/shared.auto.tfvars`,
`environments/homologacao/environment.auto.tfvars` e
`environments/producao/environment.auto.tfvars`; eles podem conter apenas
valores não sensíveis.

## Arquitetura Terraform

Os três roots operacionais têm backend, lockfile e ciclo de vida independentes:

| Root | Branch de deploy | Responsabilidade |
| --- | --- | --- |
| [`environments/shared`](environments/shared) | `main` | ECR da API, role de publicação e contrato compartilhado |
| [`environments/homologacao`](environments/homologacao) | `homolog` | Rede, EKS, role de deploy e contratos da homologação |
| [`environments/producao`](environments/producao) | `main` | Rede, EKS, role de deploy e contratos da produção |

`bootstrap/backend` cria o bucket/KMS do state e `bootstrap/identity` cria o
provider OIDC e roles separadas de plan, apply e destroy. Eles são executados
administrativamente antes dos roots operacionais. Não são usados Terraform
workspaces.

O banco gerenciado continua em seu repositório Terraform próprio. Este
repositório publica somente a rede de integração: subnets reservadas e o
security group que identifica clientes do banco. O repositório do banco consome
esses contratos e é o único owner de RDS, subnet group, backups e credenciais.

## Contratos SSM

Os módulos publicam somente parâmetros `String` não sensíveis:

- `/oficina/shared/ecr/repository-url`;
- `/oficina/<ambiente>/platform/aws-region`;
- `/oficina/<ambiente>/platform/vpc-id`;
- `/oficina/<ambiente>/platform/public-subnet-ids`;
- `/oficina/<ambiente>/platform/private-subnet-ids`;
- `/oficina/<ambiente>/platform/database-subnet-ids`;
- `/oficina/<ambiente>/platform/database-client-security-group-id`;
- `/oficina/<ambiente>/platform/eks-cluster-name`;
- `/oficina/<ambiente>/platform/api-nlb-hostname` (publicado pelo deploy Kubernetes após o Service receber hostname).

`<ambiente>` é `homologacao` ou `producao`. Senhas, tokens e connection strings
não pertencem a esse contrato nem ao state desta plataforma. O ARN da Lambda de
autenticação é publicado pelo repositório `oficina-mecanica-lambda-auth` em
`/oficina/<ambiente>/platform/auth-lambda-arn` e consumido pelo API Gateway
deste repositório.

## Integração entre repositórios

O fluxo completo e a tabela producer/consumer estão em
[Integração com lambda-auth e API](docs/runbooks/cross-repository-integration.md).
Em uma instalação nova, a ordem é: bootstrap administrativo; root `shared`;
roots de ambiente; banco e API Nest; Lambda de autenticação; deploy Kubernetes
que publica o hostname do NLB; e, por último, o API Gateway depois que os dois
contratos SSM existirem.

O endpoint público usa a URL padrão do HTTP API:
`https://<api-id>.execute-api.<region>.amazonaws.com`. Domínio customizado, ACM,
Route 53, WAF, VPC Link e CloudWatch Logs estão fora deste escopo.

## Entrega

Pull Requests para `homolog` e `main` executam verificações estáticas e, em PRs
internos, planos com OIDC read-only. O check agregado de proteção de branch é
`terraform / gate`. Após merge, o workflow de deploy usa o GitHub Environment
do stack, gera um saved plan, aplica a policy e entrega exatamente esse arquivo.

Applies automáticos só são habilitados quando a variável de repositório
`TF_DEPLOY_ENABLED` é exatamente `true`. Drift é agendado e nunca aplica
correções. Destroy existe apenas no workflow manual protegido, com confirmação
duplicada; produção permanece bloqueada por padrão.

A imagem da aplicação não é construída neste repositório. O fluxo manual em
`oficina-mecanica-api` publica uma imagem imutável no ECR. A promoção e o deploy
Kubernetes referenciam o digest versionado nos manifests, sem `latest`.

## Operação e recuperação

- [Operações Terraform](docs/runbooks/terraform-operations.md): init, plan,
  apply, drift, locks, outputs permitidos e destroy protegido.
- [Recuperação do state](docs/runbooks/state-recovery.md): contenção, seleção e
  restauração de versão S3, force-unlock e validação sem expor o state.
- [Integração entre repositórios](docs/runbooks/cross-repository-integration.md):
  provisionamento, contratos SSM, ordem de atualização e troubleshooting.
- [Promoção da imagem](docs/runbooks/plano-promocao-imagem.md): publicação da
  imagem pela API e deploy Kubernetes por digest imutável.

Use `bash scripts/terraform-check.sh` para validar formatação, os onze roots com
testes (dois bootstraps, seis módulos e três ambientes), regressões shell e
ShellCheck antes de abrir um Pull Request. Cada root usa `init -backend=false`,
`validate` e `test`, com Terraform 1.16.1 e AWS provider 5.100.0. Os testes usam
providers mock e não exigem credenciais AWS nem acesso ao backend. Para execução
offline, use `TF_CLI_CONFIG_FILE` com um filesystem mirror local do provider
fixado e preserve os lockfiles versionados.
