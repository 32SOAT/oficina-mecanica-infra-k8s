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
