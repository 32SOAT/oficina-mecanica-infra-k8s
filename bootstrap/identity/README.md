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
  CreateRole, trust/inline-policy changes and managed-policy attachment require
  the exact `${project_name}-${stack}-runtime-boundary` permissions boundary.
  The boundary is owned by this bootstrap, caps future runtime roles at regional
  discovery, the exact stack cluster and project ECR pull, and grants no IAM,
  STS, RDS, S3/state or KMS access. Controllers cannot remove, modify, version or
  delete it. Role and instance-profile reads remain scoped to the stack prefix.
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
