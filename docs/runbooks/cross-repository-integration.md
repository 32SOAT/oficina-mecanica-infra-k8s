# Integração entre infraestrutura, Lambda e API

Este runbook descreve como provisionar e conectar `oficina-mecanica-infra-k8s`,
`oficina-mecanica-lambda-auth`, o banco gerenciado e `oficina-mecanica-api`.
Cada ambiente tem state, parâmetros e credenciais isolados. Os exemplos usam
placeholders; não coloque secrets em arquivos versionados, plans, artifacts ou
logs.

## Ownership

| Recurso/contrato | Owner | Consumidor |
| --- | --- | --- |
| Backend, VPC, EKS, ECR, IAM/OIDC | infra-k8s | roots e workflows deste repositório |
| RDS, backups, credenciais e regras do banco | repositório de banco | lambda-auth e API |
| Código, bundle, Lambda e role de execução | lambda-auth | API Gateway |
| Deployment/Service Nest e hostname do NLB | infra-k8s/Kubernetes | API Gateway |
| API Gateway, rotas, stage e integrações | infra-k8s, root do ambiente | clientes públicos |
| Imagem da API | oficina-mecanica-api | deploy Kubernetes |

Nenhum recurso deve ser criado novamente em outro state. Em particular,
`lambda-auth` não cria API Gateway e este repositório não cria Lambda.

## Pré-requisitos

- AWS CLI, Terraform 1.16.1, `jq`, Docker, `kubectl` e acesso temporário à
  conta AWS correta;
- bootstrap de backend e identidade concluído, com bucket/KMS, OIDC e roles;
- GitHub Environments e variables configurados conforme
  [terraform-operations.md](terraform-operations.md);
- RDS acessível pelo cluster e pela Lambda;
- imagem da API publicada no ECR por digest, conforme
  [plano-promocao-imagem.md](plano-promocao-imagem.md).

Antes do deploy, confirme que os manifests base referenciados pelos overlays
existem em `kubernetes/oficina-api/base/`, incluindo o Job de migration. Se
essa base não estiver presente no checkout, interrompa o deploy e abra uma
correção de manifests; não substitua a base por YAML ad hoc no workflow.

Confirme a conta com `aws sts get-caller-identity` antes de operar. Não execute
comandos que imprimam state, secrets ou connection strings.

## Contratos SSM

```text
/oficina/homologacao/platform/auth-lambda-arn
/oficina/homologacao/platform/api-nlb-hostname
/oficina/producao/platform/auth-lambda-arn
/oficina/producao/platform/api-nlb-hostname
```

`lambda-auth` publica `auth-lambda-arn` após seu apply. O workflow Kubernetes
publica `api-nlb-hostname` depois que o Service `LoadBalancer` recebe o
hostname. O root de ambiente do infra-k8s consome ambos por data source e os
injeta nas integrações do API Gateway. São strings de infraestrutura; não
armazenam tokens, senhas ou connection strings.

Verifique apenas metadados e existência:

```bash
aws ssm get-parameter --name "/oficina/${ENV}/platform/auth-lambda-arn" \
  --query 'Parameter.{Name:Name,Type:Type,Version:Version}'
aws ssm get-parameter --name "/oficina/${ENV}/platform/api-nlb-hostname" \
  --query 'Parameter.{Name:Name,Type:Type,Version:Version}'
```

## Provisionamento de homologação

1. Execute os bootstraps administrativos uma única vez e valide os backends.
2. Aplique `shared` e confirme o contrato do ECR.
3. Aplique o root `homologacao` para criar VPC, EKS, IAM e contratos de rede,
   sempre usando wrappers e saved plan.
4. Provisione RDS e API Nest pelos repositórios responsáveis.
5. Publique a Lambda em `oficina-mecanica-lambda-auth` com
   `environment=homologacao`, subnets privadas, security groups e o mesmo
   `JWT_SECRET` lógico usado pela API. O apply publica `auth-lambda-arn`.
6. Publique/promova a imagem e execute o deploy Kubernetes. Aguarde migration,
   rollout e health direto do NLB. O deploy publica `api-nlb-hostname`.
7. Aguarde a consistência eventual do SSM e gere o plan do Gateway:

   ```bash
   bash scripts/terraform-init.sh homologacao
   plan_file="$(mktemp -t oficina-gateway.XXXXXX.tfplan)"
   bash scripts/terraform-plan.sh homologacao "$plan_file"
   bash scripts/terraform-plan-policy.sh homologacao "$plan_file"
   ```

8. Revise e aplique exatamente esse plan por workflow protegido. Nunca use
   apply sem saved plan.
9. Consulte os outputs permitidos e teste `POST /auth/cpf` e
   `/api/v1/health` pelo endpoint padrão do API Gateway.

Produção repete a sequência com `environment=producao`, branch `main`,
Environment protegido e aprovação independente. Não copie state, tfvars ou
secrets de homologação.

## Rotas e comportamento

| Rota | Integração | Observação |
| --- | --- | --- |
| `POST /auth/cpf` | Lambda AWS_PROXY | valida CPF e devolve JWT de cliente |
| `ANY /{proxy+}` | NLB HTTP_PROXY | encaminha `/api`, `/api/v1` e demais rotas Nest |

O stage `$default` usa auto deploy. O output `api_gateway_endpoint` é a base
pública; não acrescente stage ao caminho.

## Troubleshooting seguro

- **Lambda ausente:** execute a Lambda no ambiente correto; não crie o
  parâmetro manualmente.
- **NLB ausente:** aguarde o Service receber hostname e repita o deploy; não
  informe hostname manual no Terraform.
- **Timeout no proxy:** teste o health diretamente no NLB e confirme
  listener, target e regras de rede. A integração é HTTP e o NLB é público.
- **CPF falha, health funciona:** confira acesso da Lambda ao RDS e a
  configuração do JWT, sem imprimir secrets.
- **Plan fora do escopo:** pare e revise ownership; não importe Lambda, API
  Gateway, domínio, WAF, VPC Link, NLB ou logs em outro state.

## Validação e riscos

Execute `bash scripts/terraform-check.sh`, testes Kubernetes e gates dos
workflows. Os testes devem usar mocks ou `init -backend=false`; esta
documentação não autoriza `terraform apply`, `terraform destroy` ou deploy real
como validação local.

O NLB público aumenta a superfície de exposição e a comunicação API Gateway →
NLB usa HTTP. Trate isso como risco conhecido da arquitetura atual e inclua-o
na avaliação de segurança e no plano de evolução para integração privada com
TLS.
