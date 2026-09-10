# Operações Terraform

Este runbook cobre os roots operacionais `shared`, `homologacao` e `producao`.
Não use Terraform workspaces e não execute Terraform diretamente quando existir
um wrapper em `scripts/`.

## Pré-requisitos e configuração

Use Terraform 1.16.1, AWS CLI, `jq` e uma sessão AWS temporária na conta
correta. Exporte, sem registrar valores sensíveis no shell history:

```bash
export TF_EXPECTED_AWS_ACCOUNT_ID='<account-id>'
export TF_BACKEND_BUCKET='<bucket>'
export TF_BACKEND_REGION='us-east-1'
export TF_BACKEND_KMS_KEY_ID='<kms-key-arn>'
```

Os roots também exigem `TF_VAR_github_oidc_provider_arn` e suas permissions
boundaries. Homologação e produção exigem ainda
`TF_VAR_cluster_endpoint_public_access_cidrs`, com uma lista JSON restrita, e
as boundaries de cluster, nodes e deployer. `shared` exige a boundary do
publisher. Esses valores ficam em GitHub Variables, não em `tfvars` sensíveis.

Configure como variáveis de repositório os valores usados antes da seleção de
um Environment: `TF_DEPLOY_ENABLED`, `AWS_ACCOUNT_ID`, `TF_BACKEND_BUCKET`,
`TF_BACKEND_REGION`, `TF_BACKEND_KMS_KEY_ID`, `AWS_OIDC_PROVIDER_ARN`,
`TF_PLAN_ROLE_ARN`, `SHARED_PUBLISHER_PERMISSIONS_BOUNDARY_ARN` e, com os
prefixos `HOMOLOGACAO_` e `PRODUCAO_`, `EKS_PUBLIC_ACCESS_CIDRS_JSON`,
`CLUSTER_PERMISSIONS_BOUNDARY_ARN`, `NODE_PERMISSIONS_BOUNDARY_ARN` e
`DEPLOYER_PERMISSIONS_BOUNDARY_ARN`.

Em cada GitHub Environment (`shared`, `homologacao` e `producao`), configure os
mesmos valores comuns, `AWS_REGION`, `TF_APPLY_ROLE_ARN` e
`TF_DESTROY_ROLE_ARN`. Configure a boundary do publisher em `shared`; nos outros
dois, configure `EKS_PUBLIC_ACCESS_CIDRS_JSON` e as três boundaries sem prefixo.
Mantenha `ALLOW_PRODUCTION_DESTROY=false` ou ausente em `producao`. Não use
GitHub Secrets com access keys AWS persistentes.

## Init e plan local

Inicialize somente o stack desejado:

```bash
bash scripts/terraform-init.sh homologacao
```

Gere um saved plan fora do repositório e execute a mesma política usada no CI:

```bash
plan_file="$(mktemp -t oficina-homologacao.XXXXXX.tfplan)"
bash scripts/terraform-plan.sh homologacao "${plan_file}"
bash scripts/terraform-plan-policy.sh homologacao "${plan_file}"
```

Não envie o plan como artifact: ele pode conter valores sensíveis. Não use
`terraform show -json` em logs; o wrapper de policy processa o JSON por pipe.

## Apply

O caminho normal é merge por Pull Request em branch protegida. Um push em
`homolog` aplica homologação; um push em `main` aplica `shared`, quando afetado,
e produção. O workflow gera, valida e aplica o mesmo saved plan no mesmo job,
serializado pelo grupo `terraform-<stack>`.

O deploy Terraform permanece desligado enquanto a variável de repositório
`TF_DEPLOY_ENABLED` não for exatamente `true`. Habilite-a somente depois da
migração e verificação dos três states.

Apply local é excepcional. Revalide conta, branch, diff e saved plan e então:

```bash
export TF_ALLOW_LOCAL_APPLY=1
bash scripts/terraform-apply.sh homologacao "${plan_file}"
```

Nunca use `terraform apply` sem saved plan. Falha parcial não provoca rollback:
inspecione o state atualizado, gere um novo plan e submeta a correção.

## Drift

`Terraform Drift` roda semanalmente e também por `workflow_dispatch` para
homologação e produção, com a role de plan. O agendamento usa a default branch
`main`. No disparo manual, selecione `main`; outras refs são recusadas pelo job.
O checkout de `homolog` para homologação não altera a ref usada nas proteções
de Environment. Por isso, crie dois Environments exclusivos de leitura:

| GitHub Environment | Branch permitida para o run | Checkout | Subject OIDC da role de plan |
| --- | --- | --- | --- |
| `drift-homologacao` | Somente `main` | `homolog` | `repo:32SOAT/oficina-mecanica-infra-k8s:environment:drift-homologacao` |
| `drift-producao` | Somente `main` | `main` | `repo:32SOAT/oficina-mecanica-infra-k8s:environment:drift-producao` |

Use a regra de deployment branches selecionadas, com a branch exata `main` e
sem tags. Mantenha `main` protegida no repositório. Os dois Environments de drift
não têm required reviewers nem wait timer, para permitir execução automática.
Configure em ambos `AWS_ACCOUNT_ID`, `AWS_REGION`, `TF_BACKEND_BUCKET`,
`TF_BACKEND_REGION`, `TF_BACKEND_KMS_KEY_ID`, `AWS_OIDC_PROVIDER_ARN` e
`TF_PLAN_ROLE_ARN`. Copie do stack correspondente, sem prefixo,
`EKS_PUBLIC_ACCESS_CIDRS_JSON`, `CLUSTER_PERMISSIONS_BOUNDARY_ARN`,
`NODE_PERMISSIONS_BOUNDARY_ARN` e `DEPLOYER_PERMISSIONS_BOUNDARY_ARN`.
Não configure roles de apply/destroy nesses Environments. A trust de plan aceita
somente os dois subjects acima e `pull_request`; as roles de apply/destroy
continuam aceitando apenas seus próprios Environments.

Preserve as proteções de `homologacao` (somente `homolog`), `shared` e `producao`
(somente `main`), incluindo aprovações existentes. Crie/configure os Environments
de drift e publique a alteração administrativa de trust do bootstrap antes de
habilitar a agenda. Isso é configuração operacional separada da mudança de
código. O grupo de concorrência permanece `terraform-<stack>` junto do deploy.

Referências: [GitHub schedule](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)
e [proteções de Environment](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).

O resultado é:

- exit `0`: infraestrutura e configuração convergem;
- exit `2`: drift detectado, registrado como warning e no job summary;
- qualquer outro exit: erro operacional, como autenticação ou lock.

O workflow nunca aplica correções. Para corrigir drift, altere o Terraform ou
importe formalmente a decisão, abra PR, revise o plan e use o deploy normal.

## Locks e concorrência

O backend usa o lockfile nativo do S3 (`use_lockfile=true`). Não use
`-lock=false`. Se a aquisição do lock falhar, confirme primeiro se há um run
Terraform ativo para o mesmo stack e aguarde sua conclusão.

`force-unlock` só é permitido quando a execução proprietária terminou e o lock
é comprovadamente órfão. Copie o Lock ID exibido pelo erro, confira stack,
conta, bucket e key com outra pessoa e execute no root correto:

```bash
bash scripts/terraform-init.sh homologacao
terraform -chdir=environments/homologacao force-unlock '<LOCK_ID_EXATO>'
```

Não confirme um ID aproximado e não remova o objeto `.tflock` manualmente.

## Outputs e observabilidade

Use apenas a allowlist do wrapper:

```bash
bash scripts/terraform-output.sh homologacao cluster_name
bash scripts/terraform-state-audit.sh homologacao
```

É proibido imprimir `terraform state pull`, o conteúdo completo do state,
plans binários ou JSON de plans em logs, issues, artifacts ou mensagens. O
state pode conter segredos mesmo quando outputs públicos são não sensíveis.

## Destroy

Não há destroy cotidiano por script. Use somente `Terraform Destroy`, selecione
o stack, digite seu nome nas duas confirmações e obtenha aprovação do GitHub
Environment. O workflow valida a branch, registra a versão S3 anterior, usa a
role destroy e aplica um saved destroy plan. Produção continua indisponível
enquanto `ALLOW_PRODUCTION_DESTROY` não for exatamente `true` no ambiente
`producao`; o valor recomendado e padrão operacional é `false` ou ausente.
