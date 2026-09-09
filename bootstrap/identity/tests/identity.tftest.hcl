# These checks catch widened OIDC trust, cross-stack state writes, plan mutation,
# controller self-administration, and missing permissions/output wiring.
# Only AWS I/O is mocked: every trust and permissions document is real Terraform.
mock_provider "aws" {
  override_during = plan
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" }
  }
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/mock-network-apply" }
  }
}

override_resource {
  target          = aws_iam_role.plan
  override_during = plan
  values = {
    id  = "oficina-mecanica-terraform-plan"
    arn = "arn:aws:iam::123456789012:role/oficina-mecanica-terraform-plan"
  }
}

override_resource {
  target          = aws_iam_role.apply["shared"]
  override_during = plan
  values = {
    id  = "oficina-mecanica-terraform-shared-apply"
    arn = "arn:aws:iam::123456789012:role/oficina-mecanica-terraform-shared-apply"
  }
}

override_resource {
  target          = aws_iam_role.destroy["shared"]
  override_during = plan
  values = {
    id  = "oficina-mecanica-terraform-shared-destroy"
    arn = "arn:aws:iam::123456789012:role/oficina-mecanica-terraform-shared-destroy"
  }
}

override_resource {
  target          = aws_iam_role.apply["homologacao"]
  override_during = plan
  values = {
    id  = "oficina-mecanica-terraform-homologacao-apply"
    arn = "arn:aws:iam::123456789012:role/oficina-mecanica-terraform-homologacao-apply"
  }
}

override_resource {
  target          = aws_iam_role.destroy["homologacao"]
  override_during = plan
  values = {
    id  = "oficina-mecanica-terraform-homologacao-destroy"
    arn = "arn:aws:iam::123456789012:role/oficina-mecanica-terraform-homologacao-destroy"
  }
}

override_resource {
  target          = aws_iam_role.apply["producao"]
  override_during = plan
  values = {
    id  = "oficina-mecanica-terraform-producao-apply"
    arn = "arn:aws:iam::123456789012:role/oficina-mecanica-terraform-producao-apply"
  }
}

override_resource {
  target          = aws_iam_role.destroy["producao"]
  override_during = plan
  values = {
    id  = "oficina-mecanica-terraform-producao-destroy"
    arn = "arn:aws:iam::123456789012:role/oficina-mecanica-terraform-producao-destroy"
  }
}

variables {
  project_name      = "oficina-mecanica"
  aws_region        = "us-east-1"
  aws_account_id    = "123456789012"
  state_bucket_arn  = "arn:aws:s3:::oficina-mecanica-tfstate-123456789012"
  state_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
}

run "oidc_trust_is_exact_and_operations_are_separate" {
  command = plan

  assert {
    condition = (
      aws_iam_openid_connect_provider.github.url == "https://token.actions.githubusercontent.com" &&
      toset(aws_iam_openid_connect_provider.github.client_id_list) == toset(["sts.amazonaws.com"]) &&
      toset(aws_iam_openid_connect_provider.github.thumbprint_list) == toset(["6938fd4d98bab03faadb97b34396831e3780aea1"])
    )
    error_message = "The GitHub provider must use the approved issuer, audience and thumbprint."
  }

  assert {
    condition = alltrue([for role in concat([aws_iam_role.plan], values(aws_iam_role.apply), values(aws_iam_role.destroy)) :
      length(jsondecode(role.assume_role_policy).Statement) == 1 &&
      one(jsondecode(role.assume_role_policy).Statement).Effect == "Allow" &&
      one(jsondecode(role.assume_role_policy).Statement).Action == "sts:AssumeRoleWithWebIdentity" &&
      one(jsondecode(role.assume_role_policy).Statement).Principal.Federated == aws_iam_openid_connect_provider.github.arn &&
      keys(one(jsondecode(role.assume_role_policy).Statement).Principal) == ["Federated"] &&
      keys(one(jsondecode(role.assume_role_policy).Statement).Condition) == ["StringEquals"] &&
      one(jsondecode(role.assume_role_policy).Statement).Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com" &&
      !strcontains(role.assume_role_policy, "*")
    ])
    error_message = "Every role must trust only this provider with exact audience and subject, without wildcard or alternate trust."
  }

  assert {
    condition = toset(local.subjects.plan) == toset([
      "repo:32SOAT/oficina-mecanica-infra-k8s:pull_request",
      "repo:32SOAT/oficina-mecanica-infra-k8s:environment:homologacao",
      "repo:32SOAT/oficina-mecanica-infra-k8s:environment:producao",
    ])
    error_message = "Plan must trust only pull requests and exact homologacao/producao drift environments."
  }

  assert {
    condition = (
      alltrue([for stack in ["shared", "homologacao", "producao"] :
        one(jsondecode(aws_iam_role.apply[stack].assume_role_policy).Statement).Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:32SOAT/oficina-mecanica-infra-k8s:environment:${stack}" &&
        one(jsondecode(aws_iam_role.destroy[stack].assume_role_policy).Statement).Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:32SOAT/oficina-mecanica-infra-k8s:environment:${stack}"
      ]) &&
      length(toset(concat([aws_iam_role.plan.name], [for role in aws_iam_role.apply : role.name], [for role in aws_iam_role.destroy : role.name]))) == 7
    )
    error_message = "Apply/destroy must use the exact stack environment and separate roles."
  }
}

run "plan_can_only_read_state_and_write_its_locks" {
  command = plan

  assert {
    condition = (
      aws_iam_role_policy.plan.role == aws_iam_role.plan.id &&
      alltrue(flatten([for statement in jsondecode(aws_iam_role_policy.plan.policy).Statement : [for action in statement.Action :
        can(regex("^[a-z0-9]+:(Get|List|Describe)", action)) ||
        contains(["kms:Decrypt", "kms:GenerateDataKey", "s3:PutObject", "s3:DeleteObject"], action)
      ]])) &&
      alltrue([for statement in jsondecode(aws_iam_role_policy.plan.policy).Statement :
        (!contains(statement.Action, "s3:PutObject") && !contains(statement.Action, "s3:DeleteObject")) ||
        toset(statement.Resource) == toset([
          "arn:aws:s3:::oficina-mecanica-tfstate-123456789012/oficina/infra/shared/terraform.tfstate.tflock",
          "arn:aws:s3:::oficina-mecanica-tfstate-123456789012/oficina/infra/homologacao/terraform.tfstate.tflock",
          "arn:aws:s3:::oficina-mecanica-tfstate-123456789012/oficina/infra/producao/terraform.tfstate.tflock"
        ])
      ]) &&
      anytrue([for statement in jsondecode(aws_iam_role_policy.plan.policy).Statement : contains(statement.Action, "s3:PutObject")])
    )
    error_message = "Plan may read AWS and state, but may write only the three exact lockfiles."
  }

  assert {
    condition = alltrue([for statement in jsondecode(aws_iam_role_policy.plan.policy).Statement :
      !contains(statement.Action, "s3:GetObject") || toset(statement.Resource) == toset([
        "arn:aws:s3:::oficina-mecanica-tfstate-123456789012/oficina/infra/shared/terraform.tfstate",
        "arn:aws:s3:::oficina-mecanica-tfstate-123456789012/oficina/infra/homologacao/terraform.tfstate",
        "arn:aws:s3:::oficina-mecanica-tfstate-123456789012/oficina/infra/producao/terraform.tfstate"
      ]) || alltrue([for resource in statement.Resource : endswith(resource, ".tflock")])
    ])
    error_message = "Plan must not read bootstrap or unrelated object/state keys."
  }
}

run "backend_writes_and_kms_usage_are_scoped" {
  command = plan

  assert {
    condition = alltrue(flatten([for operation in [aws_iam_role_policy.apply, aws_iam_role_policy.destroy] : [for stack, policy in operation :
      alltrue([for statement in jsondecode(policy.policy).Statement :
        !contains(statement.Action, "s3:PutObject") ||
        alltrue([for resource in statement.Resource : contains([
          "arn:aws:s3:::oficina-mecanica-tfstate-123456789012/oficina/infra/${stack}/terraform.tfstate",
          "arn:aws:s3:::oficina-mecanica-tfstate-123456789012/oficina/infra/${stack}/terraform.tfstate.tflock"
        ], resource)])
      ]) &&
      alltrue([for statement in jsondecode(policy.policy).Statement :
        !contains(statement.Action, "s3:DeleteObject") || statement.Resource == ["arn:aws:s3:::oficina-mecanica-tfstate-123456789012/oficina/infra/${stack}/terraform.tfstate.tflock"]
      ]) &&
      anytrue([for statement in jsondecode(policy.policy).Statement : contains(statement.Action, "s3:PutObject") && contains(statement.Resource, "arn:aws:s3:::oficina-mecanica-tfstate-123456789012/oficina/infra/${stack}/terraform.tfstate")])
    ]]))
    error_message = "Each writer must persist only its own state and delete only its own lock, including destroy."
  }

  assert {
    condition = alltrue(flatten([for policy in concat([aws_iam_role_policy.plan], values(aws_iam_role_policy.apply), values(aws_iam_role_policy.destroy)) : [for statement in jsondecode(policy.policy).Statement :
      !contains(statement.Action, "kms:Decrypt") || (
        statement.Resource == [var.state_kms_key_arn] &&
        statement.Condition.StringEquals["kms:ViaService"] == "s3.us-east-1.amazonaws.com" &&
        statement.Condition.StringEquals["kms:CallerAccount"] == "123456789012" &&
        statement.Condition.StringEquals["kms:EncryptionContext:aws:s3:arn"] == var.state_bucket_arn
      )
    ]]))
    error_message = "All backend KMS access must use the supplied key, same account and S3 bucket-key context."
  }

  assert {
    condition = alltrue(flatten([for operation in [aws_iam_role_policy.apply, aws_iam_role_policy.destroy] : [for stack, policy in operation :
      alltrue([for statement in jsondecode(policy.policy).Statement : !contains(statement.Action, "s3:ListBucket") || (
        statement.Resource == [var.state_bucket_arn] &&
        toset(statement.Condition.StringEquals["s3:prefix"]) == toset(["oficina/infra/${stack}/terraform.tfstate", "oficina/infra/${stack}/terraform.tfstate.tflock"])
      )])
    ]]))
    error_message = "Bucket listing must not expose another stack or bootstrap prefix."
  }
}

run "service_permissions_separate_stacks_and_destroy" {
  command = plan

  assert {
    condition = alltrue([for policy in concat([aws_iam_role_policy.plan], values(aws_iam_role_policy.apply), values(aws_iam_role_policy.destroy), values(aws_iam_policy.network_apply)) :
      !strcontains(policy.policy, "AdministratorAccess") &&
      alltrue(flatten([for statement in jsondecode(policy.policy).Statement : [for action in statement.Action : !strcontains(action, "*")]]))
    ])
    error_message = "All permissions must enumerate actions; no wildcard actions or administrative managed policies."
  }

  assert {
    condition = (
      alltrue([for statement in jsondecode(aws_iam_role_policy.apply["shared"].policy).Statement :
        alltrue([for action in statement.Action : !startswith(action, "ec2:") && !startswith(action, "eks:") && !startswith(action, "logs:")])
      ]) &&
      alltrue([for stack in ["homologacao", "producao"] :
        alltrue(flatten([for statement in jsondecode(aws_iam_role_policy.apply[stack].policy).Statement : [for action in statement.Action :
          !startswith(action, "ecr:") || can(regex("^ecr:(Get|List|Describe)", action))
        ]])) &&
        anytrue([for statement in jsondecode(aws_iam_role_policy.apply[stack].policy).Statement : contains(statement.Action, "eks:CreateCluster")])
      ]) &&
      anytrue([for statement in jsondecode(aws_iam_role_policy.apply["shared"].policy).Statement : contains(statement.Action, "ecr:CreateRepository")])
    )
    error_message = "Shared manages ECR; only environment apply roles create EKS/network/log resources."
  }

  assert {
    condition = alltrue([for stack, policy in aws_iam_role_policy.destroy :
      policy.role == aws_iam_role.destroy[stack].id &&
      aws_iam_role_policy.apply[stack].role == aws_iam_role.apply[stack].id &&
      alltrue(flatten([for statement in jsondecode(policy.policy).Statement : [for action in statement.Action :
        !can(regex("^[a-z0-9]+:(Create|Run|Attach|Associate|PutRole|UpdateAssume)", action))
      ]])) &&
      anytrue([for statement in jsondecode(policy.policy).Statement : contains(statement.Action, "ssm:DeleteParameter")])
    ])
    error_message = "Destroy roles must attach their own policies and cannot create infrastructure or escalate IAM."
  }

  assert {
    condition = alltrue(flatten([for operation in [aws_iam_role_policy.apply, aws_iam_role_policy.destroy] : [for stack, policy in operation :
      alltrue([for statement in jsondecode(policy.policy).Statement :
        !contains(statement.Action, "iam:DeleteRole") || statement.Resource == ["arn:aws:iam::123456789012:role/oficina-mecanica-${stack}-*"]
      ]) &&
      alltrue([for statement in jsondecode(policy.policy).Statement :
        !contains(statement.Action, "ssm:DeleteParameter") || statement.Resource == ["arn:aws:ssm:us-east-1:123456789012:parameter/oficina/${stack}/*"]
      ])
    ]]))
    error_message = "IAM management excludes bootstrap controller roles; SSM writes stay inside the stack contract prefix."
  }

  assert {
    condition = (
      alltrue(flatten([for operation in [aws_iam_role_policy.apply, aws_iam_role_policy.destroy] : [for stack, policy in operation :
        length([for statement in jsondecode(policy.policy).Statement : statement
          if contains(statement.Action, "iam:ListInstanceProfilesForRole") && statement.Resource == ["arn:aws:iam::123456789012:role/oficina-mecanica-${stack}-*"]
        ]) == 1
      ]])) &&
      alltrue([for statement in jsondecode(aws_iam_role_policy.plan.policy).Statement : !contains(statement.Action, "iam:ListInstanceProfilesForRole")])
    )
    error_message = "Apply and destroy must list instance profiles only for roles in their own stack."
  }
}

run "role_specific_permissions_boundaries_are_compatible_and_protected" {
  command = plan

  assert {
    condition = (
      toset(keys(aws_iam_policy.eks_cluster_boundary)) == toset(["shared", "homologacao", "producao"]) &&
      toset(keys(aws_iam_policy.eks_node_boundary)) == toset(["shared", "homologacao", "producao"]) &&
      toset(keys(aws_iam_policy.application_boundary)) == toset(["shared", "homologacao", "producao"])
    )
    error_message = "Each stack needs separate bootstrap-managed EKS cluster, EKS node/CNI and application boundaries."
  }

  assert {
    condition = alltrue([for boundary in values(aws_iam_policy.eks_cluster_boundary) :
      length([for statement in jsondecode(boundary.policy).Statement : statement if statement.Sid == "AmazonEKSClusterPolicy"]) == 1 &&
      toset(one([for statement in jsondecode(boundary.policy).Statement : statement.Action if statement.Sid == "AmazonEKSClusterPolicy"])) == toset([
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
      ]) &&
      one([for statement in jsondecode(boundary.policy).Statement : statement.Resource if statement.Sid == "AmazonEKSClusterPolicy"]) == ["*"] &&
      !can(one([for statement in jsondecode(boundary.policy).Statement : statement if statement.Sid == "AmazonEKSClusterPolicy"]).Condition)
    ])
    error_message = "The cluster boundary must preserve the complete AmazonEKSClusterPolicy v10 action/resource contract without unsupported tag conditions."
  }

  assert {
    condition = alltrue([for boundary in values(aws_iam_policy.eks_cluster_boundary) :
      length([for statement in jsondecode(boundary.policy).Statement : statement if
        statement.Effect == "Allow" &&
        contains(statement.Action, "iam:CreateServiceLinkedRole") &&
        statement.Resource == ["*"] &&
        try(statement.Condition.StringEquals["iam:AWSServiceName"], "") == "elasticloadbalancing.amazonaws.com"
      ]) == 1 &&
      length([for statement in jsondecode(boundary.policy).Statement : statement if
        statement.Effect == "Allow" &&
        contains(statement.Action, "ec2:DeleteNetworkInterface") &&
        statement.Resource == ["*"] &&
        try(statement.Condition.StringEquals["ec2:ResourceTag/eks:eni:owner"], "") == "amazon-vpc-cni"
      ]) == 1 &&
      length([for statement in jsondecode(boundary.policy).Statement : statement if
        statement.Effect == "Deny" &&
        statement.Action == ["kms:DescribeKey"] &&
        statement.Resource == ["arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"]
      ]) == 1
    ])
    error_message = "Cluster IAM/ENI exceptions must use the official conditions and the Terraform state KMS key must remain explicitly denied."
  }

  assert {
    condition = alltrue([for boundary in values(aws_iam_policy.eks_node_boundary) :
      toset(flatten([for statement in jsondecode(boundary.policy).Statement : statement.Action if statement.Effect == "Allow"])) == toset([
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
        "ec2:AssignPrivateIpAddresses",
        "ec2:AttachNetworkInterface",
        "ec2:CreateNetworkInterface",
        "ec2:DeleteNetworkInterface",
        "ec2:DescribeTags",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DetachNetworkInterface",
        "ec2:ModifyNetworkInterfaceAttribute",
        "ec2:UnassignPrivateIpAddresses",
        "ec2:CreateTags",
        "ecr:GetAuthorizationToken",
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
      ]) &&
      length([for statement in jsondecode(boundary.policy).Statement : statement if statement.Sid == "AmazonEKSWorkerNodePolicy" && statement.Resource == ["*"] && !can(statement.Condition)]) == 1 &&
      length([for statement in jsondecode(boundary.policy).Statement : statement if statement.Sid == "AmazonEKSCNIPolicy" && statement.Resource == ["*"] && !can(statement.Condition)]) == 1 &&
      length([for statement in jsondecode(boundary.policy).Statement : statement if
        statement.Sid == "AmazonEKSCNIPolicyENITag" &&
        statement.Action == ["ec2:CreateTags"] &&
        statement.Resource == ["arn:aws:ec2:us-east-1:123456789012:network-interface/*"] &&
        !can(statement.Condition)
      ]) == 1
    ])
    error_message = "The node boundary must preserve the complete WorkerNode v3, CNI v6 and ECR ReadOnly v3 contract without unsupported tag conditions."
  }

  assert {
    condition = alltrue([for stack, boundary in aws_iam_policy.eks_cluster_boundary :
      length([for statement in jsondecode(boundary.policy).Statement : statement if statement.Sid == "DenyCrossStackEC2Mutations"]) == 1 &&
      toset(one([for statement in jsondecode(boundary.policy).Statement : statement.Action if statement.Sid == "DenyCrossStackEC2Mutations"])) == toset([
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
      ]) &&
      toset(one([for statement in jsondecode(boundary.policy).Statement : statement.Resource if statement.Sid == "DenyCrossStackEC2Mutations"])) == toset([
        "arn:aws:ec2:us-east-1:123456789012:instance/*",
        "arn:aws:ec2:us-east-1:123456789012:network-interface/*",
        "arn:aws:ec2:us-east-1:123456789012:route-table/*",
        "arn:aws:ec2:us-east-1:123456789012:security-group/*",
        "arn:aws:ec2:us-east-1:123456789012:volume/*",
      ]) &&
      try(one([for statement in jsondecode(boundary.policy).Statement : statement if statement.Sid == "DenyCrossStackEC2Mutations"]).Condition.StringEquals["aws:ResourceTag/Project"], "") == "oficina-mecanica" &&
      try(one([for statement in jsondecode(boundary.policy).Statement : statement if statement.Sid == "DenyCrossStackEC2Mutations"]).Condition.StringNotEquals["aws:ResourceTag/Environment"], "") == stack &&
      try(one([for statement in jsondecode(boundary.policy).Statement : statement if statement.Sid == "DenyCrossStackEC2Mutations"]).Condition.Null["aws:ResourceTag/Environment"], "") == "false" &&
      length([for statement in jsondecode(boundary.policy).Statement : statement if
        statement.Sid == "DenyCrossStackSecurityGroupCreationParent" &&
        statement.Effect == "Deny" &&
        statement.Action == ["ec2:CreateSecurityGroup"] &&
        statement.Resource == ["arn:aws:ec2:us-east-1:123456789012:vpc/*"] &&
        try(statement.Condition.StringEquals["aws:ResourceTag/Project"], "") == "oficina-mecanica" &&
        try(statement.Condition.StringNotEquals["aws:ResourceTag/Environment"], "") == stack &&
        try(statement.Condition.Null["aws:ResourceTag/Environment"], "") == "false"
      ]) == 1 &&
      length([for statement in jsondecode(boundary.policy).Statement : statement if
        statement.Sid == "DenyCrossStackELBMutations" &&
        statement.Effect == "Deny" &&
        toset(statement.Action) == toset([
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
        ]) &&
        toset(statement.Resource) == toset([
          "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/*",
          "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/*",
          "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/*",
        ]) &&
        try(statement.Condition.StringEquals["aws:ResourceTag/Project"], "") == "oficina-mecanica" &&
        try(statement.Condition.StringNotEquals["aws:ResourceTag/Environment"], "") == stack &&
        try(statement.Condition.Null["aws:ResourceTag/Environment"], "") == "false"
      ]) == 1 &&
      length([for statement in jsondecode(boundary.policy).Statement : statement if
        statement.Sid == "DenyCrossStackAutoScalingMutation" &&
        statement.Effect == "Deny" &&
        statement.Action == ["autoscaling:UpdateAutoScalingGroup"] &&
        statement.Resource == ["arn:aws:autoscaling:us-east-1:123456789012:autoScalingGroup:*:autoScalingGroupName/*"] &&
        try(statement.Condition.StringEquals["aws:ResourceTag/Project"], "") == "oficina-mecanica" &&
        try(statement.Condition.StringNotEquals["aws:ResourceTag/Environment"], "") == stack &&
        try(statement.Condition.Null["aws:ResourceTag/Environment"], "") == "false"
      ]) == 1
    ])
    error_message = "Cluster Resource * allows must be counterbalanced by supported resource-tag denies for EC2, ELB and Auto Scaling resources explicitly owned by another stack."
  }

  assert {
    condition = alltrue([for stack, boundary in aws_iam_policy.eks_node_boundary :
      length([for statement in jsondecode(boundary.policy).Statement : statement if
        statement.Sid == "DenyCrossStackENIMutations" &&
        statement.Effect == "Deny" &&
        toset(statement.Action) == toset([
          "ec2:AssignPrivateIpAddresses",
          "ec2:AttachNetworkInterface",
          "ec2:CreateTags",
          "ec2:DeleteNetworkInterface",
          "ec2:DetachNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:UnassignPrivateIpAddresses",
        ]) &&
        toset(statement.Resource) == toset([
          "arn:aws:ec2:us-east-1:123456789012:instance/*",
          "arn:aws:ec2:us-east-1:123456789012:network-interface/*",
        ]) &&
        try(statement.Condition.StringEquals["aws:ResourceTag/Project"], "") == "oficina-mecanica" &&
        try(statement.Condition.StringNotEquals["aws:ResourceTag/Environment"], "") == stack &&
        try(statement.Condition.Null["aws:ResourceTag/Environment"], "") == "false"
      ]) == 1 &&
      length([for statement in jsondecode(boundary.policy).Statement : statement if
        statement.Sid == "DenyCrossStackENICreationParents" &&
        statement.Effect == "Deny" &&
        statement.Action == ["ec2:CreateNetworkInterface"] &&
        toset(statement.Resource) == toset([
          "arn:aws:ec2:us-east-1:123456789012:security-group/*",
          "arn:aws:ec2:us-east-1:123456789012:subnet/*",
        ]) &&
        try(statement.Condition.StringEquals["aws:ResourceTag/Project"], "") == "oficina-mecanica" &&
        try(statement.Condition.StringNotEquals["aws:ResourceTag/Environment"], "") == stack &&
        try(statement.Condition.Null["aws:ResourceTag/Environment"], "") == "false"
      ]) == 1
    ])
    error_message = "Node Resource * allows must deny mutations of tagged ENIs/instances and ENI creation through tagged network parents owned by another stack."
  }

  assert {
    condition = alltrue(flatten([for boundaries in [aws_iam_policy.eks_cluster_boundary, aws_iam_policy.eks_node_boundary, aws_iam_policy.application_boundary] : [for stack, boundary in boundaries :
      length(boundary.policy) <= 6144 &&
      alltrue(flatten([for statement in jsondecode(boundary.policy).Statement : [for action in statement.Action :
        !contains(["sts", "rds", "s3"], split(":", action)[0]) &&
        !strcontains(action, "*") &&
        (split(":", action)[0] != "iam" || action == "iam:CreateServiceLinkedRole") &&
        (split(":", action)[0] != "kms" || action == "kms:DescribeKey")
      ]])) &&
      alltrue(flatten([for statement in jsondecode(boundary.policy).Statement : [for resource in statement.Resource :
        alltrue([for other_stack in ["shared", "homologacao", "producao"] : other_stack == stack || !strcontains(resource, other_stack)])
      ]]))
    ]]))
    error_message = "All boundaries must fit IAM quota and exclude wildcard actions, prohibited services, administrative IAM/KMS use and cross-stack ARNs."
  }

  assert {
    condition = alltrue([for boundary in values(aws_iam_policy.application_boundary) :
      alltrue(flatten([for statement in jsondecode(boundary.policy).Statement : [for action in statement.Action :
        !contains(["iam", "kms", "sts", "rds", "s3"], split(":", action)[0])
      ]]))
    ])
    error_message = "Application boundaries must not inherit the narrowly scoped IAM/KMS exceptions required only by the EKS cluster role."
  }

  assert {
    condition = alltrue([for stack, policy in aws_iam_policy.role_delegation :
      alltrue([for contract in [
        { role = "arn:aws:iam::123456789012:role/oficina-mecanica-${stack}-eks-cluster", boundary = "arn:aws:iam::123456789012:policy/oficina-mecanica-${stack}-eks-cluster-boundary" },
        { role = "arn:aws:iam::123456789012:role/oficina-mecanica-${stack}-eks-node", boundary = "arn:aws:iam::123456789012:policy/oficina-mecanica-${stack}-eks-node-boundary" },
        { role = "arn:aws:iam::123456789012:role/oficina-mecanica-${stack}-*", boundary = "arn:aws:iam::123456789012:policy/oficina-mecanica-${stack}-runtime-boundary" },
        ] : length([for statement in jsondecode(policy.policy).Statement : statement if
          statement.Effect == "Allow" &&
          contains(statement.Action, "iam:CreateRole") &&
          statement.Resource == [contract.role] &&
          try(statement.Condition.StringEquals["iam:PermissionsBoundary"], "") == contract.boundary
        ]) == 1
      ])
    ])
    error_message = "Role delegation must select the exact protected boundary for cluster, node or future stack roles."
  }

  assert {
    condition = alltrue([for stack, policy in aws_iam_policy.role_delegation :
      alltrue([for contract in [
        { role = "arn:aws:iam::123456789012:role/oficina-mecanica-${stack}-eks-cluster", boundary = "arn:aws:iam::123456789012:policy/oficina-mecanica-${stack}-eks-cluster-boundary" },
        { role = "arn:aws:iam::123456789012:role/oficina-mecanica-${stack}-eks-node", boundary = "arn:aws:iam::123456789012:policy/oficina-mecanica-${stack}-eks-node-boundary" },
        ] : length([for statement in jsondecode(policy.policy).Statement : statement if
          statement.Effect == "Deny" &&
          contains(statement.Action, "iam:CreateRole") &&
          statement.Resource == [contract.role] &&
          try(statement.Condition.ArnNotEquals["iam:PermissionsBoundary"], "") == contract.boundary
        ]) == 1
      ])
    ])
    error_message = "The wildcard application contract must not let exact EKS roles select another boundary."
  }

  assert {
    condition = alltrue([for stack in ["homologacao", "producao"] :
      length([for statement in jsondecode(aws_iam_policy.role_delegation[stack].policy).Statement : statement if
        contains(statement.Action, "iam:AttachRolePolicy") &&
        statement.Resource == ["arn:aws:iam::123456789012:role/oficina-mecanica-${stack}-eks-cluster"] &&
        try(statement.Condition.StringEquals["iam:PermissionsBoundary"], "") == "arn:aws:iam::123456789012:policy/oficina-mecanica-${stack}-eks-cluster-boundary" &&
        statement.Condition.ArnEquals["iam:PolicyARN"] == ["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"]
      ]) == 1 &&
      length([for statement in jsondecode(aws_iam_policy.role_delegation[stack].policy).Statement : statement if
        contains(statement.Action, "iam:AttachRolePolicy") &&
        statement.Resource == ["arn:aws:iam::123456789012:role/oficina-mecanica-${stack}-eks-node"] &&
        try(statement.Condition.StringEquals["iam:PermissionsBoundary"], "") == "arn:aws:iam::123456789012:policy/oficina-mecanica-${stack}-eks-node-boundary" &&
        toset(statement.Condition.ArnEquals["iam:PolicyARN"]) == toset([
          "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
          "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
          "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
        ])
      ]) == 1
    ])
    error_message = "Cluster and node managed policies must attach only to their exact roles with their matching boundaries."
  }

  assert {
    condition = alltrue([for policy in concat(values(aws_iam_role_policy.apply), values(aws_iam_role_policy.destroy), values(aws_iam_policy.network_apply), values(aws_iam_policy.role_delegation)) :
      alltrue(flatten([for statement in jsondecode(policy.policy).Statement : [for action in statement.Action : !contains([
        "iam:DeleteRolePermissionsBoundary", "iam:CreatePolicyVersion", "iam:SetDefaultPolicyVersion", "iam:DeletePolicyVersion", "iam:DeletePolicy",
      ], action)]]))
    ])
    error_message = "Controllers must not remove boundaries or modify, version or delete managed policies."
  }

  assert {
    condition = alltrue([for stack, attachment in aws_iam_role_policy_attachment.role_delegation :
      attachment.role == aws_iam_role.apply[stack].name && attachment.policy_arn == aws_iam_policy.role_delegation[stack].arn
    ])
    error_message = "Each apply controller must receive its bootstrap-managed role-delegation policy."
  }
}

run "outputs_reference_the_managed_identities" {
  command = plan
  assert {
    condition = (
      output.github_oidc_provider_arn == aws_iam_openid_connect_provider.github.arn &&
      output.plan_role_arn == aws_iam_role.plan.arn &&
      output.shared_apply_role_arn == aws_iam_role.apply["shared"].arn &&
      output.homologacao_apply_role_arn == aws_iam_role.apply["homologacao"].arn &&
      output.producao_apply_role_arn == aws_iam_role.apply["producao"].arn &&
      output.shared_destroy_role_arn == aws_iam_role.destroy["shared"].arn &&
      output.homologacao_destroy_role_arn == aws_iam_role.destroy["homologacao"].arn &&
      output.producao_destroy_role_arn == aws_iam_role.destroy["producao"].arn
      && alltrue([for stack in ["shared", "homologacao", "producao"] :
        output.permissions_boundary_arns[stack].eks_cluster == aws_iam_policy.eks_cluster_boundary[stack].arn &&
        output.permissions_boundary_arns[stack].eks_node == aws_iam_policy.eks_node_boundary[stack].arn &&
        output.permissions_boundary_arns[stack].application == aws_iam_policy.application_boundary[stack].arn
      ])
    )
    error_message = "The bootstrap outputs must expose the managed identities and unambiguous role-specific boundary ARNs."
  }
}

run "reject_wildcard_organization" {
  command = plan
  variables { github_organization = "32SOAT*" }
  expect_failures = [var.github_organization]
}

run "reject_other_repository" {
  command = plan
  variables { github_repository = "another-repository" }
  expect_failures = [var.github_repository]
}

run "reject_wildcard_bucket" {
  command = plan
  variables { state_bucket_arn = "arn:aws:s3:::*" }
  expect_failures = [var.state_bucket_arn]
}

run "reject_cross_account_key" {
  command = plan
  variables { state_kms_key_arn = "arn:aws:kms:us-east-1:210987654321:key/11111111-2222-3333-4444-555555555555" }
  expect_failures = [var.state_kms_key_arn]
}

run "reject_invalid_account" {
  command = plan
  variables { aws_account_id = "*" }
  expect_failures = [var.aws_account_id]
}

run "policies_fit_iam_quota_and_bound_global_actions" {
  command = plan

  assert {
    condition = alltrue([for policy in concat([aws_iam_role_policy.plan], values(aws_iam_role_policy.apply), values(aws_iam_role_policy.destroy)) :
      length(policy.policy) <= 10240
    ])
    error_message = "Each role's inline policies must fit the 10,240-character IAM quota."
  }

  assert {
    condition = alltrue([for stack, policy in aws_iam_policy.network_apply :
      length(policy.policy) <= 6144 &&
      aws_iam_role_policy_attachment.network_apply[stack].role == aws_iam_role.apply[stack].name &&
      aws_iam_role_policy_attachment.network_apply[stack].policy_arn == policy.arn &&
      alltrue([for statement in jsondecode(policy.policy).Statement :
        alltrue([for action in statement.Action : startswith(action, "ec2:")]) &&
        alltrue([for resource in statement.Resource : startswith(resource, "arn:aws:ec2:us-east-1:123456789012:")])
      ])
    ]) && toset(keys(aws_iam_role_policy_attachment.network_apply)) == toset(["homologacao", "producao"])
    error_message = "EC2 managed policies fit 6,144 characters, stay region/account scoped and attach only to environment apply roles."
  }

  assert {
    condition = alltrue([for stack, policy in aws_iam_policy.role_delegation :
      length(policy.policy) <= 6144 &&
      aws_iam_role_policy_attachment.role_delegation[stack].role == aws_iam_role.apply[stack].name &&
      aws_iam_role_policy_attachment.role_delegation[stack].policy_arn == policy.arn
    ])
    error_message = "Role-delegation managed policies must fit 6,144 characters and attach only to their stack apply role."
  }

  assert {
    condition = alltrue(flatten([for policy in concat([aws_iam_role_policy.plan], values(aws_iam_role_policy.apply), values(aws_iam_role_policy.destroy), values(aws_iam_policy.network_apply)) : [for statement in jsondecode(policy.policy).Statement :
      !contains(statement.Resource, "*") || (
        try(statement.Condition.StringEquals["aws:RequestedRegion"], "") == "us-east-1" &&
        alltrue([for action in statement.Action : contains([
          "ec2:DescribeAvailabilityZones", "ec2:DescribeVpcs", "ec2:DescribeSubnets", "ec2:DescribeRouteTables", "ec2:DescribeInternetGateways", "ec2:DescribeAddresses", "ec2:DescribeAddressesAttribute", "ec2:DescribeNatGateways", "ec2:DescribeSecurityGroups", "ec2:DescribeSecurityGroupRules", "ec2:DescribeNetworkInterfaces", "ec2:DescribeTags",
          "eks:DescribeAddonVersions", "eks:DescribeAddonConfiguration", "logs:DescribeLogGroups", "eks:CreateCluster"
        ], action)])
      )
    ]]))
    error_message = "Only documented APIs without resource authorization may use Resource *, always region-bound."
  }

  assert {
    condition = alltrue([for stack in ["homologacao", "producao"] :
      alltrue([for statement in jsondecode(aws_iam_role_policy.apply[stack].policy).Statement :
        !contains(statement.Action, "eks:CreateCluster") || (
          try(statement.Condition.StringEquals["aws:RequestTag/Project"], "") == "oficina-mecanica" &&
          try(statement.Condition.StringEquals["aws:RequestTag/Environment"], "") == stack
        )
      ]) &&
      alltrue([for statement in jsondecode(aws_iam_role_policy.destroy[stack].policy).Statement :
        !contains(statement.Action, "ec2:DeleteVpc") || (
          try(statement.Condition.StringEquals["aws:ResourceTag/Project"], "") == "oficina-mecanica" &&
          try(statement.Condition.StringEquals["aws:ResourceTag/Environment"], "") == stack
        )
      ])
    ])
    error_message = "EKS creation and network destruction must enforce project/environment ownership."
  }
}
