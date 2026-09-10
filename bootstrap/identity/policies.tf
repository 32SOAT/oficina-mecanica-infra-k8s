locals {
  regional_arn = "${var.aws_region}:${var.aws_account_id}"
  state_keys   = { for stack in local.stacks : stack => "oficina/infra/${stack}/terraform.tfstate" }
  state_arns   = { for stack, key in local.state_keys : stack => "${var.state_bucket_arn}/${key}" }
  role_arns    = { for stack in local.stacks : stack => "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${stack}-*" }
  permissions_boundary_arns = { for stack in local.stacks : stack => {
    application   = "arn:aws:iam::${var.aws_account_id}:policy/${var.project_name}-${stack}-runtime-boundary"
    eks_cluster   = "arn:aws:iam::${var.aws_account_id}:policy/${var.project_name}-${stack}-eks-cluster-boundary"
    eks_node      = "arn:aws:iam::${var.aws_account_id}:policy/${var.project_name}-${stack}-eks-node-boundary"
    api_publisher = stack == "shared" ? "arn:aws:iam::${var.aws_account_id}:policy/${var.project_name}-shared-api-publisher-boundary" : null
    api_deployer  = contains(local.environments, stack) ? "arn:aws:iam::${var.aws_account_id}:policy/${var.project_name}-${stack}-api-deployer-boundary" : null
  } }
  eks_role_arns = { for stack in local.stacks : stack => {
    cluster = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${stack}-eks-cluster"
    node    = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${stack}-eks-node"
  } }
  api_identity_role_arns = { for stack in local.stacks : stack =>
    "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${stack}-${stack == "shared" ? "api-publisher" : "api-deployer"}"
  }
  api_identity_boundary_arns = { for stack in local.stacks : stack =>
    stack == "shared" ? local.permissions_boundary_arns[stack].api_publisher : local.permissions_boundary_arns[stack].api_deployer
  }
  delegated_role_actions = ["iam:CreateRole", "iam:PutRolePermissionsBoundary", "iam:PutRolePolicy", "iam:UpdateAssumeRolePolicy"]
  eks_managed_policies_by_role = {
    cluster = ["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"]
    node = [
      "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
      "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
      "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    ]
  }
  cluster_arns          = { for stack in local.stacks : stack => "arn:aws:eks:${local.regional_arn}:cluster/${var.project_name}-${stack}" }
  ecr_arn               = "arn:aws:ecr:${local.regional_arn}:repository/${var.project_name}-api"
  ecr_url_parameter_arn = "arn:aws:ssm:${local.regional_arn}:parameter/oficina/shared/ecr/repository-url"
  platform_parameter_arns = { for stack in local.environments : stack => [for name in [
    "aws-region",
    "vpc-id",
    "public-subnet-ids",
    "private-subnet-ids",
    "database-subnet-ids",
    "database-client-security-group-id",
    "eks-cluster-name",
  ] : "arn:aws:ssm:${local.regional_arn}:parameter/oficina/${stack}/platform/${name}"] }
  eks_arns = { for stack in local.environments : stack => [
    local.cluster_arns[stack],
    "arn:aws:eks:${local.regional_arn}:nodegroup/${var.project_name}-${stack}/*",
    "arn:aws:eks:${local.regional_arn}:addon/${var.project_name}-${stack}/*",
    "arn:aws:eks:${local.regional_arn}:access-entry/${var.project_name}-${stack}/*",
  ] }
  network_arns = [for kind in ["vpc", "subnet", "route-table", "internet-gateway", "elastic-ip", "natgateway", "security-group"] :
    "arn:aws:ec2:${local.regional_arn}:${kind}/*"
  ]
  network_create_actions = ["ec2:CreateVpc", "ec2:CreateSubnet", "ec2:CreateRouteTable", "ec2:CreateInternetGateway", "ec2:AllocateAddress", "ec2:CreateNatGateway", "ec2:CreateSecurityGroup"]
  network_delete_actions = ["ec2:DeleteVpc", "ec2:DeleteSubnet", "ec2:DeleteRouteTable", "ec2:DeleteInternetGateway", "ec2:ReleaseAddress", "ec2:DeleteNatGateway", "ec2:DeleteSecurityGroup", "ec2:DeleteRoute", "ec2:DisassociateRouteTable", "ec2:DetachInternetGateway", "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress"]
  network_read_actions   = ["ec2:DescribeAvailabilityZones", "ec2:DescribeVpcs", "ec2:DescribeSubnets", "ec2:DescribeRouteTables", "ec2:DescribeInternetGateways", "ec2:DescribeAddresses", "ec2:DescribeAddressesAttribute", "ec2:DescribeNatGateways", "ec2:DescribeSecurityGroups", "ec2:DescribeSecurityGroupRules", "ec2:DescribeNetworkInterfaces", "ec2:DescribeTags"]
  eks_read_actions       = ["eks:DescribeCluster", "eks:DescribeNodegroup", "eks:DescribeAddon", "eks:DescribeAccessEntry", "eks:DescribeUpdate", "eks:ListNodegroups", "eks:ListAddons", "eks:ListAccessEntries", "eks:ListAssociatedAccessPolicies", "eks:ListTagsForResource", "eks:ListUpdates"]
  eks_delete_actions     = ["eks:DeleteCluster", "eks:DeleteNodegroup", "eks:DeleteAddon", "eks:DeleteAccessEntry", "eks:DisassociateAccessPolicy"]
  eks_managed_policies   = concat(local.eks_managed_policies_by_role.cluster, local.eks_managed_policies_by_role.node)

  # S3 bucket keys use the bucket ARN (not the object ARN) as encryption context.
  # GenerateDataKey is required even by plan for SSE-KMS PutObject on .tflock;
  # only the S3 statements grant object writes. No direct KMS use is allowed.
  backend_kms = {
    Sid      = "BackendEncryption"
    Effect   = "Allow"
    Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    Resource = [var.state_kms_key_arn]
    Condition = { StringEquals = {
      "kms:CallerAccount"                = var.aws_account_id
      "kms:ViaService"                   = "s3.${var.aws_region}.amazonaws.com"
      "kms:EncryptionContext:aws:s3:arn" = var.state_bucket_arn
    } }
  }
  backend = { for scope, stacks in merge({ plan = sort(tolist(local.stacks)) }, { for stack in local.stacks : stack => [stack] }) : scope => [
    {
      Sid       = "ListStateKeys"
      Effect    = "Allow"
      Action    = ["s3:ListBucket"]
      Resource  = [var.state_bucket_arn]
      Condition = { StringEquals = { "s3:prefix" = flatten([for stack in stacks : [local.state_keys[stack], "${local.state_keys[stack]}.tflock"]]) } }
    },
    {
      Sid      = "StateObjects"
      Effect   = "Allow"
      Action   = scope == "plan" ? ["s3:GetObject"] : ["s3:GetObject", "s3:PutObject"]
      Resource = [for stack in stacks : local.state_arns[stack]]
    },
    {
      Sid      = "StateLockfiles"
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      Resource = [for stack in stacks : "${local.state_arns[stack]}.tflock"]
    },
    local.backend_kms,
  ] }

  common_read = { for stack in local.stacks : stack => [
    {
      Sid      = "ReadRoles${stack}"
      Effect   = "Allow"
      Action   = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListRoleTags"]
      Resource = [local.role_arns[stack]]
    },
    {
      Sid      = "ReadContracts${stack}"
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:ListTagsForResource"]
      Resource = ["arn:aws:ssm:${local.regional_arn}:parameter/oficina/${stack}/*"]
    },
  ] }
  ecr_read = [{
    Sid      = "ReadRepository"
    Effect   = "Allow"
    Action   = ["ecr:DescribeRepositories", "ecr:GetRepositoryPolicy", "ecr:GetLifecyclePolicy", "ecr:ListTagsForResource", "ecr:DescribeImages", "ecr:ListImages"]
    Resource = [local.ecr_arn]
  }]
  # AWS does not support resource-level authorization for these discovery APIs.
  # Region still bounds them. Global IAM reads below use exact policy/provider ARNs.
  environment_read = { for stack in local.environments : stack => [
    {
      Sid       = "ReadVpcAttributes${stack}"
      Effect    = "Allow"
      Action    = ["ec2:DescribeVpcAttribute"]
      Resource  = ["arn:aws:ec2:${local.regional_arn}:vpc/*"]
      Condition = { StringEquals = { "aws:ResourceTag/Project" = var.project_name, "aws:ResourceTag/Environment" = stack } }
    },
    {
      Sid       = "RegionalDiscovery${stack}"
      Effect    = "Allow"
      Action    = concat(local.network_read_actions, ["eks:DescribeAddonVersions", "eks:DescribeAddonConfiguration", "logs:DescribeLogGroups"])
      Resource  = ["*"]
      Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
    },
    {
      Sid      = "ReadEKS${stack}"
      Effect   = "Allow"
      Action   = local.eks_read_actions
      Resource = local.eks_arns[stack]
    },
    {
      Sid      = "ReadLogTags${stack}"
      Effect   = "Allow"
      Action   = ["logs:ListTagsLogGroup", "logs:ListTagsForResource"]
      Resource = ["arn:aws:logs:${local.regional_arn}:log-group:/aws/eks/${var.project_name}-${stack}/cluster", "arn:aws:logs:${local.regional_arn}:log-group:/aws/eks/${var.project_name}-${stack}/cluster:*"]
    },
    {
      Sid      = "ReadEKSManagedPolicies${stack}"
      Effect   = "Allow"
      Action   = ["iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions"]
      Resource = local.eks_managed_policies
    },
  ] }
  oidc_read = [{
    Sid      = "ReadGitHubProvider"
    Effect   = "Allow"
    Action   = ["iam:GetOpenIDConnectProvider"]
    Resource = [aws_iam_openid_connect_provider.github.arn]
  }]
  stack_read = { for stack in local.stacks : stack => concat(
    local.common_read[stack], local.oidc_read, local.ecr_read,
    try(local.environment_read[stack], [])
  ) }

  common_delete = { for stack in local.stacks : stack => [
    {
      Sid      = "ListStackRoleInstanceProfiles"
      Effect   = "Allow"
      Action   = ["iam:ListInstanceProfilesForRole"]
      Resource = [local.role_arns[stack]]
    },
    {
      Sid      = "RemoveStackRoles"
      Effect   = "Allow"
      Action   = ["iam:DeleteRole", "iam:DeleteRolePolicy"]
      Resource = [local.role_arns[stack]]
    },
    {
      Sid       = "DetachEKSManagedPolicies"
      Effect    = "Allow"
      Action    = ["iam:DetachRolePolicy"]
      Resource  = [local.role_arns[stack]]
      Condition = { ArnEquals = { "iam:PolicyARN" = local.eks_managed_policies } }
    },
    {
      Sid      = "RemoveContracts"
      Effect   = "Allow"
      Action   = ["ssm:DeleteParameter"]
      Resource = ["arn:aws:ssm:${local.regional_arn}:parameter/oficina/${stack}/*"]
    },
  ] }
  role_delegation = { for stack in local.stacks : stack => [
    {
      Sid      = "ManageApplicationRoles"
      Effect   = "Allow"
      Action   = local.delegated_role_actions
      Resource = [local.role_arns[stack]]
      Condition = { StringEquals = {
        "iam:PermissionsBoundary" = local.permissions_boundary_arns[stack].application
      } }
    },
    {
      Sid      = "ManageAPIIdentityRole"
      Effect   = "Allow"
      Action   = local.delegated_role_actions
      Resource = [local.api_identity_role_arns[stack]]
      Condition = { StringEquals = {
        "iam:PermissionsBoundary" = local.api_identity_boundary_arns[stack]
      } }
    },
    {
      Sid      = "RejectWrongAPIIdentityBoundary"
      Effect   = "Deny"
      Action   = local.delegated_role_actions
      Resource = [local.api_identity_role_arns[stack]]
      Condition = { ArnNotEquals = {
        "iam:PermissionsBoundary" = local.api_identity_boundary_arns[stack]
      } }
    },
    {
      Sid      = "ManageEKSClusterRole"
      Effect   = "Allow"
      Action   = local.delegated_role_actions
      Resource = [local.eks_role_arns[stack].cluster]
      Condition = { StringEquals = {
        "iam:PermissionsBoundary" = local.permissions_boundary_arns[stack].eks_cluster
      } }
    },
    {
      Sid      = "ManageEKSNodeRole"
      Effect   = "Allow"
      Action   = local.delegated_role_actions
      Resource = [local.eks_role_arns[stack].node]
      Condition = { StringEquals = {
        "iam:PermissionsBoundary" = local.permissions_boundary_arns[stack].eks_node
      } }
    },
    {
      Sid      = "RejectWrongEKSClusterBoundary"
      Effect   = "Deny"
      Action   = local.delegated_role_actions
      Resource = [local.eks_role_arns[stack].cluster]
      Condition = { ArnNotEquals = {
        "iam:PermissionsBoundary" = local.permissions_boundary_arns[stack].eks_cluster
      } }
    },
    {
      Sid      = "RejectWrongEKSNodeBoundary"
      Effect   = "Deny"
      Action   = local.delegated_role_actions
      Resource = [local.eks_role_arns[stack].node]
      Condition = { ArnNotEquals = {
        "iam:PermissionsBoundary" = local.permissions_boundary_arns[stack].eks_node
      } }
    },
    {
      Sid      = "AttachEKSClusterPolicy"
      Effect   = "Allow"
      Action   = ["iam:AttachRolePolicy"]
      Resource = [local.eks_role_arns[stack].cluster]
      Condition = {
        ArnEquals    = { "iam:PolicyARN" = local.eks_managed_policies_by_role.cluster }
        StringEquals = { "iam:PermissionsBoundary" = local.permissions_boundary_arns[stack].eks_cluster }
      }
    },
    {
      Sid      = "AttachEKSNodePolicies"
      Effect   = "Allow"
      Action   = ["iam:AttachRolePolicy"]
      Resource = [local.eks_role_arns[stack].node]
      Condition = {
        ArnEquals    = { "iam:PolicyARN" = local.eks_managed_policies_by_role.node }
        StringEquals = { "iam:PermissionsBoundary" = local.permissions_boundary_arns[stack].eks_node }
      }
    },
  ] }
  common_apply = { for stack in local.stacks : stack => [
    {
      Sid      = "UpdateStackRoleMetadata"
      Effect   = "Allow"
      Action   = ["iam:UpdateRole", "iam:TagRole", "iam:UntagRole"]
      Resource = [local.role_arns[stack]]
    },
    {
      Sid      = "PublishContracts"
      Effect   = "Allow"
      Action   = ["ssm:PutParameter", "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource"]
      Resource = ["arn:aws:ssm:${local.regional_arn}:parameter/oficina/${stack}/*"]
    },
  ] }
  ecr_delete = [{
    Sid      = "RemoveRepository"
    Effect   = "Allow"
    Action   = ["ecr:DeleteRepository", "ecr:DeleteRepositoryPolicy", "ecr:DeleteLifecyclePolicy"]
    Resource = [local.ecr_arn]
  }]
  ecr_apply = [{
    Sid      = "ManageRepository"
    Effect   = "Allow"
    Action   = ["ecr:CreateRepository", "ecr:PutImageTagMutability", "ecr:PutImageScanningConfiguration", "ecr:SetRepositoryPolicy", "ecr:PutLifecyclePolicy", "ecr:TagResource", "ecr:UntagResource"]
    Resource = [local.ecr_arn]
  }]
  environment_delete = { for stack in local.environments : stack => [
    {
      Sid       = "RemoveOwnedNetwork"
      Effect    = "Allow"
      Action    = local.network_delete_actions
      Resource  = local.network_arns
      Condition = { StringEquals = { "aws:ResourceTag/Project" = var.project_name, "aws:ResourceTag/Environment" = stack } }
    },
    {
      Sid      = "RemoveEKS"
      Effect   = "Allow"
      Action   = local.eks_delete_actions
      Resource = local.eks_arns[stack]
    },
    {
      Sid      = "RemoveControlPlaneLogs"
      Effect   = "Allow"
      Action   = ["logs:DeleteLogGroup", "logs:DeleteRetentionPolicy"]
      Resource = ["arn:aws:logs:${local.regional_arn}:log-group:/aws/eks/${var.project_name}-${stack}/cluster:*"]
    },
  ] }
  environment_apply = { for stack in local.environments : stack => [
    {
      Sid       = "CreateTaggedNetwork"
      Effect    = "Allow"
      Action    = local.network_create_actions
      Resource  = local.network_arns
      Condition = { StringEquals = { "aws:RequestTag/Project" = var.project_name, "aws:RequestTag/Environment" = stack } }
    },
    {
      # Creating a subnet/route table/SG/NAT also authorizes its existing parents.
      Sid       = "UseOwnedNetworkParents"
      Effect    = "Allow"
      Action    = ["ec2:CreateSubnet", "ec2:CreateRouteTable", "ec2:CreateSecurityGroup", "ec2:CreateNatGateway"]
      Resource  = [for kind in ["vpc", "subnet", "elastic-ip"] : "arn:aws:ec2:${local.regional_arn}:${kind}/*"]
      Condition = { StringEquals = { "aws:ResourceTag/Project" = var.project_name, "aws:ResourceTag/Environment" = stack } }
    },
    {
      Sid       = "TagNetworkOnCreation"
      Effect    = "Allow"
      Action    = ["ec2:CreateTags"]
      Resource  = local.network_arns
      Condition = { StringEquals = { "ec2:CreateAction" = [for action in local.network_create_actions : trimprefix(action, "ec2:")] } }
    },
    {
      Sid       = "UpdateOwnedNetwork"
      Effect    = "Allow"
      Action    = ["ec2:ModifyVpcAttribute", "ec2:ModifySubnetAttribute", "ec2:CreateRoute", "ec2:ReplaceRoute", "ec2:AssociateRouteTable", "ec2:ReplaceRouteTableAssociation", "ec2:AttachInternetGateway", "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress"]
      Resource  = local.network_arns
      Condition = { StringEquals = { "aws:ResourceTag/Project" = var.project_name, "aws:ResourceTag/Environment" = stack } }
    },
    {
      Sid      = "UpdateOwnedNetworkTags"
      Effect   = "Allow"
      Action   = ["ec2:CreateTags", "ec2:DeleteTags"]
      Resource = local.network_arns
      Condition = {
        StringEquals                   = { "aws:ResourceTag/Project" = var.project_name, "aws:ResourceTag/Environment" = stack }
        "ForAllValues:StringNotEquals" = { "aws:TagKeys" = ["Project", "Environment"] }
      }
    },
    {
      # CreateCluster has no resource-level ARN support in the AWS SAR.
      Sid      = "CreateTaggedEKSCluster"
      Effect   = "Allow"
      Action   = ["eks:CreateCluster"]
      Resource = ["*"]
      Condition = { StringEquals = {
        "aws:RequestedRegion" = var.aws_region, "aws:RequestTag/Project" = var.project_name, "aws:RequestTag/Environment" = stack
      } }
    },
    {
      Sid      = "ManageEKS"
      Effect   = "Allow"
      Action   = ["eks:UpdateClusterConfig", "eks:UpdateClusterVersion", "eks:CreateNodegroup", "eks:UpdateNodegroupConfig", "eks:UpdateNodegroupVersion", "eks:CreateAddon", "eks:UpdateAddon", "eks:CreateAccessEntry", "eks:UpdateAccessEntry", "eks:AssociateAccessPolicy", "eks:TagResource", "eks:UntagResource"]
      Resource = local.eks_arns[stack]
    },
    {
      Sid      = "ManageControlPlaneLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:PutRetentionPolicy", "logs:TagLogGroup", "logs:UntagLogGroup", "logs:TagResource", "logs:UntagResource"]
      Resource = ["arn:aws:logs:${local.regional_arn}:log-group:/aws/eks/${var.project_name}-${stack}/cluster", "arn:aws:logs:${local.regional_arn}:log-group:/aws/eks/${var.project_name}-${stack}/cluster:*"]
    },
    {
      Sid       = "PassEKSServiceRoles"
      Effect    = "Allow"
      Action    = ["iam:PassRole"]
      Resource  = ["arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${stack}-eks-*"]
      Condition = { StringEquals = { "iam:PassedToService" = ["eks.amazonaws.com", "ec2.amazonaws.com"] } }
    },
    {
      Sid       = "CreateEKSServiceLinkedRoles"
      Effect    = "Allow"
      Action    = ["iam:CreateServiceLinkedRole"]
      Resource  = ["arn:aws:iam::${var.aws_account_id}:role/aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS", "arn:aws:iam::${var.aws_account_id}:role/aws-service-role/eks-nodegroup.amazonaws.com/AWSServiceRoleForAmazonEKSNodegroup"]
      Condition = { StringEquals = { "iam:AWSServiceName" = ["eks.amazonaws.com", "eks-nodegroup.amazonaws.com"] } }
    },
  ] }
}

# These maxima are owned by the administrative bootstrap. Stack controllers can
# require them on runtime roles but cannot modify, version or delete them.
resource "aws_iam_policy" "application_boundary" {
  for_each    = local.stacks
  name        = "${var.project_name}-${each.key}-runtime-boundary"
  description = "Maximum application runtime permissions for ${each.key} roles."
  tags        = merge(local.tags, { Stack = each.key })
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RegionalRuntimeDiscovery"
        Effect = "Allow"
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications",
          "ec2:DescribeVpcs",
        ]
        Resource  = ["*"]
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid      = "UseOwnCluster"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster", "eks-auth:AssumeRoleForPodIdentity"]
        Resource = [local.cluster_arns[each.key]]
      },
      {
        Sid      = "RequestRegistryAuthorization"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
        Condition = { StringEquals = {
          "aws:RequestedRegion" = var.aws_region
        } }
      },
      {
        Sid      = "PullProjectImages"
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:DescribeImages", "ecr:GetDownloadUrlForLayer"]
        Resource = [local.ecr_arn]
      },
    ]
  })
}

resource "aws_iam_policy" "api_publisher_boundary" {
  for_each    = toset(["shared"])
  name        = "${var.project_name}-${each.key}-api-publisher-boundary"
  description = "Maximum manual API image publishing permissions."
  tags        = merge(local.tags, { Stack = each.key })
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AuthenticateToRegionalECR"
        Effect    = "Allow"
        Action    = ["ecr:GetAuthorizationToken"]
        Resource  = ["*"]
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid      = "ReadRepositoryContract"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = [local.ecr_url_parameter_arn]
      },
      {
        Sid    = "UploadProjectImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = [local.ecr_arn]
      },
    ]
  })
}

resource "aws_iam_policy" "api_deployer_boundary" {
  for_each    = local.environments
  name        = "${var.project_name}-${each.key}-api-deployer-boundary"
  description = "Maximum API deployment permissions for ${each.key}."
  tags        = merge(local.tags, { Stack = each.key })
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DiscoverOwnCluster"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = [local.cluster_arns[each.key]]
      },
      {
        Sid      = "ReadEnvironmentContract"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = local.platform_parameter_arns[each.key]
      },
      {
        Sid      = "ValidateProjectImage"
        Effect   = "Allow"
        Action   = ["ecr:DescribeImages"]
        Resource = [local.ecr_arn]
      },
    ]
  })
}

resource "aws_iam_policy" "eks_cluster_boundary" {
  for_each    = local.stacks
  name        = "${var.project_name}-${each.key}-eks-cluster-boundary"
  description = "Maximum EKS cluster service permissions for ${each.key}."
  tags        = merge(local.tags, { Stack = each.key })
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AmazonEKSClusterPolicy"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:UpdateAutoScalingGroup",
          "ec2:AttachVolume",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateRoute",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:CreateVolume",
          "ec2:DeleteRoute",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteVolume",
          "ec2:DescribeInstances",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications",
          "ec2:DescribeVpcs",
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeAvailabilityZones",
          "ec2:DetachVolume",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyVolume",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeInstanceTopology",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
          "elasticloadbalancing:AttachLoadBalancerToSubnets",
          "elasticloadbalancing:ConfigureHealthCheck",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateLoadBalancerListeners",
          "elasticloadbalancing:CreateLoadBalancerPolicy",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancerListeners",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeLoadBalancerPolicies",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DetachLoadBalancerFromSubnets",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
          "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
          "kms:DescribeKey",
        ]
        Resource = ["*"]
      },
      {
        Sid      = "AmazonEKSClusterPolicySLRCreate"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = ["*"]
        Condition = { StringEquals = {
          "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
        } }
      },
      {
        Sid      = "AmazonEKSClusterPolicyENIDelete"
        Effect   = "Allow"
        Action   = ["ec2:DeleteNetworkInterface"]
        Resource = ["*"]
        Condition = { StringEquals = {
          "ec2:ResourceTag/eks:eni:owner" = "amazon-vpc-cni"
        } }
      },
      {
        Sid      = "ProtectTerraformStateKey"
        Effect   = "Deny"
        Action   = ["kms:DescribeKey"]
        Resource = [var.state_kms_key_arn]
      },
      {
        Sid    = "DenyCrossStackEC2Mutations"
        Effect = "Deny"
        Action = [
          "ec2:AttachVolume",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateRoute",
          "ec2:CreateTags",
          "ec2:DeleteNetworkInterface",
          "ec2:DeleteRoute",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteVolume",
          "ec2:DetachVolume",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyVolume",
          "ec2:RevokeSecurityGroupIngress",
        ]
        Resource = [
          "arn:aws:ec2:${local.regional_arn}:instance/*",
          "arn:aws:ec2:${local.regional_arn}:network-interface/*",
          "arn:aws:ec2:${local.regional_arn}:route-table/*",
          "arn:aws:ec2:${local.regional_arn}:security-group/*",
          "arn:aws:ec2:${local.regional_arn}:volume/*",
        ]
        Condition = {
          StringEquals    = { "aws:ResourceTag/Project" = var.project_name }
          StringNotEquals = { "aws:ResourceTag/Environment" = each.key }
          Null            = { "aws:ResourceTag/Environment" = "false" }
        }
      },
      {
        Sid    = "DenyCrossStackELBMutations"
        Effect = "Deny"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:ApplySecurityGroupsToLoadBalancer",
          "elasticloadbalancing:AttachLoadBalancerToSubnets",
          "elasticloadbalancing:ConfigureHealthCheck",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateLoadBalancerListeners",
          "elasticloadbalancing:CreateLoadBalancerPolicy",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteLoadBalancerListeners",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DetachLoadBalancerFromSubnets",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:RegisterInstancesWithLoadBalancer",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:SetLoadBalancerPoliciesForBackendServer",
          "elasticloadbalancing:SetLoadBalancerPoliciesOfListener",
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:${local.regional_arn}:listener/*",
          "arn:aws:elasticloadbalancing:${local.regional_arn}:loadbalancer/*",
          "arn:aws:elasticloadbalancing:${local.regional_arn}:targetgroup/*",
        ]
        Condition = {
          StringEquals    = { "aws:ResourceTag/Project" = var.project_name }
          StringNotEquals = { "aws:ResourceTag/Environment" = each.key }
          Null            = { "aws:ResourceTag/Environment" = "false" }
        }
      },
      {
        Sid      = "DenyCrossStackSecurityGroupCreationParent"
        Effect   = "Deny"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = ["arn:aws:ec2:${local.regional_arn}:vpc/*"]
        Condition = {
          StringEquals    = { "aws:ResourceTag/Project" = var.project_name }
          StringNotEquals = { "aws:ResourceTag/Environment" = each.key }
          Null            = { "aws:ResourceTag/Environment" = "false" }
        }
      },
      {
        Sid      = "DenyCrossStackAutoScalingMutation"
        Effect   = "Deny"
        Action   = ["autoscaling:UpdateAutoScalingGroup"]
        Resource = ["arn:aws:autoscaling:${local.regional_arn}:autoScalingGroup:*:autoScalingGroupName/*"]
        Condition = {
          StringEquals    = { "aws:ResourceTag/Project" = var.project_name }
          StringNotEquals = { "aws:ResourceTag/Environment" = each.key }
          Null            = { "aws:ResourceTag/Environment" = "false" }
        }
      },
    ]
  })
}

resource "aws_iam_policy" "eks_node_boundary" {
  for_each    = local.stacks
  name        = "${var.project_name}-${each.key}-eks-node-boundary"
  description = "Maximum EKS node and CNI permissions for ${each.key}."
  tags        = merge(local.tags, { Stack = each.key })
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AmazonEKSWorkerNodePolicy"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVolumes",
          "ec2:DescribeVolumesModifications",
          "ec2:DescribeVpcs",
          "eks:DescribeCluster",
          "eks-auth:AssumeRoleForPodIdentity",
        ]
        Resource = ["*"]
      },
      {
        Sid    = "AmazonEKSCNIPolicy"
        Effect = "Allow"
        Action = [
          "ec2:AssignPrivateIpAddresses",
          "ec2:AttachNetworkInterface",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DetachNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:UnassignPrivateIpAddresses",
        ]
        Resource = ["*"]
      },
      {
        Sid      = "AmazonEKSCNIPolicyENITag"
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = ["arn:aws:ec2:${local.regional_arn}:network-interface/*"]
      },
      {
        Sid      = "AmazonEC2ContainerRegistryAuthorization"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      },
      {
        Sid    = "AmazonEC2ContainerRegistryReadOnly"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:GetLifecyclePolicy",
          "ecr:GetLifecyclePolicyPreview",
          "ecr:ListTagsForResource",
          "ecr:DescribeImageScanFindings",
        ]
        Resource = [local.ecr_arn]
      },
      {
        Sid    = "DenyCrossStackENIMutations"
        Effect = "Deny"
        Action = [
          "ec2:AssignPrivateIpAddresses",
          "ec2:AttachNetworkInterface",
          "ec2:CreateTags",
          "ec2:DeleteNetworkInterface",
          "ec2:DetachNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:UnassignPrivateIpAddresses",
        ]
        Resource = [
          "arn:aws:ec2:${local.regional_arn}:instance/*",
          "arn:aws:ec2:${local.regional_arn}:network-interface/*",
        ]
        Condition = {
          StringEquals    = { "aws:ResourceTag/Project" = var.project_name }
          StringNotEquals = { "aws:ResourceTag/Environment" = each.key }
          Null            = { "aws:ResourceTag/Environment" = "false" }
        }
      },
      {
        Sid    = "DenyCrossStackENICreationParents"
        Effect = "Deny"
        Action = ["ec2:CreateNetworkInterface"]
        Resource = [
          "arn:aws:ec2:${local.regional_arn}:security-group/*",
          "arn:aws:ec2:${local.regional_arn}:subnet/*",
        ]
        Condition = {
          StringEquals    = { "aws:ResourceTag/Project" = var.project_name }
          StringNotEquals = { "aws:ResourceTag/Environment" = each.key }
          Null            = { "aws:ResourceTag/Environment" = "false" }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "plan" {
  name = "terraform-plan"
  role = aws_iam_role.plan.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.backend.plan, local.oidc_read, local.ecr_read,
      flatten([for stack in local.stacks : local.common_read[stack]]),
      flatten([for stack in local.environments : local.environment_read[stack]])
    )
  })
}

resource "aws_iam_role_policy" "apply" {
  for_each = local.stacks
  name     = "terraform-apply-${each.key}"
  role     = aws_iam_role.apply[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.backend[each.key], local.stack_read[each.key], local.common_delete[each.key], local.common_apply[each.key],
      merge(local.environment_delete, { shared = local.ecr_delete })[each.key],
      merge({ for stack, statements in local.environment_apply : stack => slice(statements, 5, length(statements)) }, { shared = local.ecr_apply })[each.key]
    )
  })
}

resource "aws_iam_role_policy" "destroy" {
  for_each = local.stacks
  name     = "terraform-destroy-${each.key}"
  role     = aws_iam_role.destroy[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(local.backend[each.key], local.stack_read[each.key], local.common_delete[each.key],
      merge(local.environment_delete, { shared = local.ecr_delete })[each.key]
    )
  })
}

# A role's aggregate inline quota is 10,240 characters. Keep EC2 creation/update
# in a dedicated customer-managed policy (6,144-character quota), never an AWS
# administrative managed policy. Destroy retains only its inline delete actions.
resource "aws_iam_policy" "network_apply" {
  for_each    = local.environments
  name        = "${var.project_name}-terraform-${each.key}-network-apply"
  description = "Tagged network creation and updates for ${each.key}."
  tags        = merge(local.tags, { Stack = each.key })
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = slice(local.environment_apply[each.key], 0, 5)
  })
}

resource "aws_iam_role_policy_attachment" "network_apply" {
  for_each   = local.environments
  role       = aws_iam_role.apply[each.key].name
  policy_arn = aws_iam_policy.network_apply[each.key].arn
}

resource "aws_iam_policy" "role_delegation" {
  for_each    = local.stacks
  name        = "${var.project_name}-terraform-${each.key}-role-delegation"
  description = "Boundary-enforced role delegation for ${each.key}."
  tags        = merge(local.tags, { Stack = each.key })
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.role_delegation[each.key]
  })
}

resource "aws_iam_role_policy_attachment" "role_delegation" {
  for_each   = local.stacks
  role       = aws_iam_role.apply[each.key].name
  policy_arn = aws_iam_policy.role_delegation[each.key].arn
}
