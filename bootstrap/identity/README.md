# Terraform identities

Administrative root, initialized with a partial S3 backend. It consumes
`project_name`, `aws_region`, `aws_account_id`, `state_bucket_arn` and
`state_kms_key_arn` from the operator/backend bootstrap, plus optional `tags`.
The GitHub organization/repository inputs accept only `32SOAT` and
`oficina-mecanica-infra-k8s`. No AWS account lookup or remote-state dependency
is required to construct these policies.

The seven controller roles use the `${project_name}-terraform-` name prefix.
Plan trusts exactly `repo:32SOAT/oficina-mecanica-infra-k8s:pull_request` plus
the `environment:homologacao` and `environment:producao` subjects used by
scheduled drift. It does not trust `shared` or any other environment subject.
Each stack has distinct apply and destroy roles that both trust its exact
`repo:32SOAT/oficina-mecanica-infra-k8s:environment:<stack>` subject, where
`<stack>` is `shared`, `homologacao` or `producao`. All trusts use
`StringEquals`, the GitHub OIDC provider and audience `sts.amazonaws.com`.
Environment branch/reviewer protections and the manual destroy workflow remain
responsible for operation approval; an OIDC environment subject does not encode
the workflow name. Drift therefore runs through the protected homologacao or
producao environment while retaining the read-only plan permissions.

## Resource contracts

- State keys are fixed to `oficina/infra/<stack>/terraform.tfstate`, matching the
  shell wrappers. No operational role can access bootstrap state. Plan reads the
  three operational states and writes/deletes only their exact `.tflock` objects.
  Apply/destroy may write only their own state and delete only their own lock.
  Bucket listing uses exact `s3:prefix` conditions, not an entire bucket grant.
- Backend KMS usage is restricted to the supplied key, account, S3 regional
  service and bucket encryption context. `kms:GenerateDataKey` is needed by
  plan for SSE-KMS lock writes. The backend enables S3 bucket keys, which use
  the bucket ARN as encryption context. This preserves account-IAM delegation
  from the backend bootstrap without referring to future roles in its key policy.
- ECR is `${project_name}-api`. Only shared apply/destroy manages it; Terraform
  roles receive no image upload or batch image deletion permissions.
- EKS cluster names are `${project_name}-${stack}`; nodegroup, add-on and access
  entry ARNs use that exact cluster prefix. Logs are under
  `/aws/eks/${project_name}-${stack}/cluster`.
- Stack-managed IAM roles are `${project_name}-${stack}-*`, excluding Terraform
  controllers. EKS service roles use `${project_name}-${stack}-eks-*`. Managed
  policy attachment is limited to the four enumerated EKS/node policies;
  `PassRole` is limited to these service roles and EKS/EC2 service principals.
  CreateRole and trust/inline-policy changes require exact bootstrap-owned
  boundaries: `${project_name}-${stack}-eks-cluster-boundary`
  for `${project_name}-${stack}-eks-cluster`,
  `${project_name}-${stack}-eks-node-boundary` for
  `${project_name}-${stack}-eks-node`, or
  `${project_name}-${stack}-runtime-boundary` for other current and future stack
  roles. The deterministic `${project_name}-shared-api-publisher` role instead
  requires its `api-publisher-boundary`; homologacao/producao
  `${project_name}-${stack}-api-deployer` roles require their matching
  `api-deployer-boundary`. These maxima grant only the ECR, EKS and SSM calls
  used by their corresponding API workflows. The generic runtime boundary has
  no ECR upload permission. EKS managed-policy attachment is split across the
  exact cluster and node roles and requires their matching boundary. The cluster maximum mirrors
  the complete `AmazonEKSClusterPolicy` v10 action/resource contract, including
  its official ELB service-linked-role and orphaned-CNI ENI conditions. It allows
  only read-only `kms:DescribeKey` and explicitly denies that action on the
  Terraform state key. The node maximum combines the complete
  `AmazonEKSWorkerNodePolicy` v3 and `AmazonEKS_CNI_Policy` v6 contracts with the
  `AmazonEC2ContainerRegistryReadOnly` v3 actions scoped to the project ECR where
  resource-level authorization is available. The inherent `Resource = "*"`
  scope of EKS/EC2 discovery and CNI mutations is preserved so the boundaries do
  not nullify their attached AWS policies. Explicit denies isolate supported
  EC2, ELB, Auto Scaling and ENI mutations whenever a target is identified by
  `Project = project_name` and an `Environment` different from the boundary's
  stack. The denies require the Environment tag to exist, so own-stack and
  untagged resources remain operable. Security-group and ENI creation is also
  denied through an existing VPC, subnet or security group tagged for another
  stack; listener and load-balancer-policy creation is denied on an existing
  load balancer tagged for another stack. AWS does not expose a guaranteed
  existing resource-tag context for every create call, so new load balancers,
  target groups and resources whose parents are untagged remain outside this
  guardrail until ownership tags exist.
  Neither maximum grants STS, RDS, S3, KMS use beyond `DescribeKey`, nor IAM
  beyond the conditioned ELB service-linked role creation. Controllers cannot
  remove, modify, version or delete a boundary.
  `permissions_boundary_arns` exposes an
  unambiguous `eks_cluster`, `eks_node` and `application` ARN for every stack,
  plus `api_publisher` for shared and `api_deployer` for each environment, so
  downstream modules can apply the correct contract. Role and instance-profile
  reads remain scoped to the stack prefix.
- Network resources and EKS creation must carry `Project = project_name` and
  `Environment = stack`. Network parents, updates and deletion enforce those
  ownership tags. Existing resources must receive those tags through the approved
  administrative migration before these roles can modify them. Apply cannot
  change or remove the ownership tags on existing network resources.
- SSM contracts are scoped to `parameter/oficina/<stack>/*`; ECR metadata may be
  read by all operational roles. No RDS, database state or database secret access
  is granted.
- Apply has deletion permissions needed by reviewed replacements. Destroy has
  reads, teardown actions and its backend writes, with no creation or IAM policy
  creation/update. EC2 apply permissions are two customer-managed policies,
  attached only to homologacao/producao apply roles, to respect IAM's policy
  size limits; they are not administrative AWS managed policies.

## APIs requiring global resource scope

The following enumerated APIs do not support resource-level authorization in
the AWS Service Authorization Reference and therefore use `Resource = ["*"]`.
Every such statement includes `aws:RequestedRegion = aws_region`:

- EC2 discovery: `DescribeAvailabilityZones`, `DescribeVpcs`, `DescribeSubnets`,
  `DescribeRouteTables`, `DescribeInternetGateways`, `DescribeAddresses`,
  `DescribeAddressesAttribute`, `DescribeNatGateways`, `DescribeSecurityGroups`,
  `DescribeSecurityGroupRules`, `DescribeNetworkInterfaces`, `DescribeTags`.
- EKS discovery: `DescribeAddonVersions`, `DescribeAddonConfiguration`.
- CloudWatch Logs discovery: `DescribeLogGroups`.
- EKS `CreateCluster`, additionally requiring exact Project/Environment request
  tags. Subsequent cluster operations are restricted to the stack cluster ARN.

`DescribeVpcAttribute` supports VPC ARNs and uses a separate scoped statement.
Wildcards inside EC2 IDs, stack-owned IAM names, SSM suffixes, EKS child IDs and
log-group descendants cover resources not yet created; their account, region,
ownership tags or stack prefixes remain fixed. No action contains a wildcard.

References: [EC2 authorization](https://docs.aws.amazon.com/service-authorization/latest/reference/list_ec2.html),
[EKS authorization](https://docs.aws.amazon.com/service-authorization/latest/reference/list_eks.html),
[CloudWatch Logs authorization](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazoncloudwatchlogs.html).

## Local verification

Use Terraform 1.16.1 and the committed AWS 5.100.0 lockfile:

```sh
terraform -chdir=bootstrap/identity init -backend=false -input=false
terraform -chdir=bootstrap/identity fmt -check -recursive
terraform -chdir=bootstrap/identity validate
terraform -chdir=bootstrap/identity test
```

Every test run uses `command = plan` with a mock AWS provider. Tests decode real
trust/permissions JSON, validate outputs with distinct mocked role identities,
and check inline/customer-managed policy quotas. They do not simulate AWS IAM
authorization end to end and do not contact AWS or mutate remote state.
