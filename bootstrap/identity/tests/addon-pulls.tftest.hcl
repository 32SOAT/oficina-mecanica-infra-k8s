# Pull permissions are evaluated from the emitted boundary, not an ARN local.
# Missing sidecars, using the project account for AWS images, a default-account
# fallback in opt-in regions, wildcard repositories or ECR writes must fail.
mock_provider "aws" {
  override_during = plan
}

variables {
  project_name      = "oficina-mecanica"
  aws_region        = "us-east-1"
  aws_account_id    = "123456789012"
  state_bucket_arn  = "arn:aws:s3:::oficina-mecanica-tfstate-123456789012"
  state_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
}

run "reject_unmapped_registry_region" {
  command = plan
  variables {
    aws_region        = "us-east-99"
    state_kms_key_arn = "arn:aws:kms:us-east-99:123456789012:key/11111111-2222-3333-4444-555555555555"
  }
  expect_failures = [var.aws_region]
}

run "node_pulls_official_addons_us_east_1" {
  command = plan
  variables {
    aws_region        = "us-east-1"
    state_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition = alltrue([for boundary in values(aws_iam_policy.eks_node_boundary) :
      alltrue([for action in ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"] :
        toset(flatten([for statement in jsondecode(boundary.policy).Statement : statement.Resource if
          statement.Effect == "Allow" && contains(statement.Action, action) && !can(statement.Condition)
          ])) == toset([
          "arn:aws:ecr:us-east-1:123456789012:repository/oficina-mecanica-api",
          "arn:aws:ecr:us-east-1:602401143452:repository/amazon-k8s-cni",
          "arn:aws:ecr:us-east-1:602401143452:repository/amazon-k8s-cni-init",
          "arn:aws:ecr:us-east-1:602401143452:repository/amazon/aws-network-policy-agent",
          "arn:aws:ecr:us-east-1:602401143452:repository/eks/coredns",
          "arn:aws:ecr:us-east-1:602401143452:repository/eks/kube-proxy",
          "arn:aws:ecr:us-east-1:602401143452:repository/eks/eks-pod-identity-agent",
          "arn:aws:ecr:us-east-1:602401143452:repository/eks/aws-ebs-csi-driver",
          "arn:aws:ecr:us-east-1:602401143452:repository/eks/csi-attacher",
          "arn:aws:ecr:us-east-1:602401143452:repository/eks/csi-provisioner",
          "arn:aws:ecr:us-east-1:602401143452:repository/eks/csi-resizer",
          "arn:aws:ecr:us-east-1:602401143452:repository/eks/csi-snapshotter",
          "arn:aws:ecr:us-east-1:602401143452:repository/eks/livenessprobe",
          "arn:aws:ecr:us-east-1:602401143452:repository/eks/csi-node-driver-registrar",
          "arn:aws:ecr:us-east-1:602401143452:repository/eks/volume-modifier-for-k8s",
        ])
      ]) &&
      alltrue([for statement in jsondecode(boundary.policy).Statement :
        statement.Effect != "Allow" || !anytrue([for resource in statement.Resource : strcontains(resource, ":602401143452:repository/")]) ||
        toset(statement.Action) == toset(["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"])
      ]) &&
      alltrue(flatten([for statement in jsondecode(boundary.policy).Statement : [for action in statement.Action :
        !startswith(action, "ecr:") ||
        (statement.Effect == "Allow" && can(regex("^ecr:(Get|List|Describe|BatchGet|BatchCheck)", action)))
      ]])) &&
      anytrue([for statement in jsondecode(boundary.policy).Statement :
        statement.Effect == "Allow" && statement.Action == ["ecr:GetAuthorizationToken"] && statement.Resource == ["*"]
      ]) &&
      length(boundary.policy) <= 6144
    ])
    error_message = "Nodes must pull only the application and exact official add-on repositories in us-east-1, using registry 602401143452, without allowing ECR writes or exceeding IAM quota."
  }
}

run "node_pulls_official_addons_sa_east_1" {
  command = plan
  variables {
    aws_region        = "sa-east-1"
    state_kms_key_arn = "arn:aws:kms:sa-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition = alltrue([for boundary in values(aws_iam_policy.eks_node_boundary) :
      alltrue([for action in ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"] :
        toset(flatten([for statement in jsondecode(boundary.policy).Statement : statement.Resource if
          statement.Effect == "Allow" && contains(statement.Action, action) && !can(statement.Condition)
          ])) == toset([
          "arn:aws:ecr:sa-east-1:123456789012:repository/oficina-mecanica-api",
          "arn:aws:ecr:sa-east-1:602401143452:repository/amazon-k8s-cni",
          "arn:aws:ecr:sa-east-1:602401143452:repository/amazon-k8s-cni-init",
          "arn:aws:ecr:sa-east-1:602401143452:repository/amazon/aws-network-policy-agent",
          "arn:aws:ecr:sa-east-1:602401143452:repository/eks/coredns",
          "arn:aws:ecr:sa-east-1:602401143452:repository/eks/kube-proxy",
          "arn:aws:ecr:sa-east-1:602401143452:repository/eks/eks-pod-identity-agent",
          "arn:aws:ecr:sa-east-1:602401143452:repository/eks/aws-ebs-csi-driver",
          "arn:aws:ecr:sa-east-1:602401143452:repository/eks/csi-attacher",
          "arn:aws:ecr:sa-east-1:602401143452:repository/eks/csi-provisioner",
          "arn:aws:ecr:sa-east-1:602401143452:repository/eks/csi-resizer",
          "arn:aws:ecr:sa-east-1:602401143452:repository/eks/csi-snapshotter",
          "arn:aws:ecr:sa-east-1:602401143452:repository/eks/livenessprobe",
          "arn:aws:ecr:sa-east-1:602401143452:repository/eks/csi-node-driver-registrar",
          "arn:aws:ecr:sa-east-1:602401143452:repository/eks/volume-modifier-for-k8s",
        ])
      ]) &&
      alltrue([for statement in jsondecode(boundary.policy).Statement :
        statement.Effect != "Allow" || !anytrue([for resource in statement.Resource : strcontains(resource, ":602401143452:repository/")]) ||
        toset(statement.Action) == toset(["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"])
      ]) &&
      alltrue(flatten([for statement in jsondecode(boundary.policy).Statement : [for action in statement.Action :
        !startswith(action, "ecr:") ||
        (statement.Effect == "Allow" && can(regex("^ecr:(Get|List|Describe|BatchGet|BatchCheck)", action)))
      ]])) &&
      anytrue([for statement in jsondecode(boundary.policy).Statement :
        statement.Effect == "Allow" && statement.Action == ["ecr:GetAuthorizationToken"] && statement.Resource == ["*"]
      ]) &&
      length(boundary.policy) <= 6144
    ])
    error_message = "Nodes must pull only the application and exact official add-on repositories in sa-east-1, using registry 602401143452, without allowing ECR writes or exceeding IAM quota."
  }
}

run "node_pulls_official_addons_me_central_1" {
  command = plan
  variables {
    aws_region        = "me-central-1"
    state_kms_key_arn = "arn:aws:kms:me-central-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition = alltrue([for boundary in values(aws_iam_policy.eks_node_boundary) :
      alltrue([for action in ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"] :
        toset(flatten([for statement in jsondecode(boundary.policy).Statement : statement.Resource if
          statement.Effect == "Allow" && contains(statement.Action, action) && !can(statement.Condition)
          ])) == toset([
          "arn:aws:ecr:me-central-1:123456789012:repository/oficina-mecanica-api",
          "arn:aws:ecr:me-central-1:759879836304:repository/amazon-k8s-cni",
          "arn:aws:ecr:me-central-1:759879836304:repository/amazon-k8s-cni-init",
          "arn:aws:ecr:me-central-1:759879836304:repository/amazon/aws-network-policy-agent",
          "arn:aws:ecr:me-central-1:759879836304:repository/eks/coredns",
          "arn:aws:ecr:me-central-1:759879836304:repository/eks/kube-proxy",
          "arn:aws:ecr:me-central-1:759879836304:repository/eks/eks-pod-identity-agent",
          "arn:aws:ecr:me-central-1:759879836304:repository/eks/aws-ebs-csi-driver",
          "arn:aws:ecr:me-central-1:759879836304:repository/eks/csi-attacher",
          "arn:aws:ecr:me-central-1:759879836304:repository/eks/csi-provisioner",
          "arn:aws:ecr:me-central-1:759879836304:repository/eks/csi-resizer",
          "arn:aws:ecr:me-central-1:759879836304:repository/eks/csi-snapshotter",
          "arn:aws:ecr:me-central-1:759879836304:repository/eks/livenessprobe",
          "arn:aws:ecr:me-central-1:759879836304:repository/eks/csi-node-driver-registrar",
          "arn:aws:ecr:me-central-1:759879836304:repository/eks/volume-modifier-for-k8s",
        ])
      ]) &&
      alltrue([for statement in jsondecode(boundary.policy).Statement :
        statement.Effect != "Allow" || !anytrue([for resource in statement.Resource : strcontains(resource, ":759879836304:repository/")]) ||
        toset(statement.Action) == toset(["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"])
      ]) &&
      alltrue(flatten([for statement in jsondecode(boundary.policy).Statement : [for action in statement.Action :
        !startswith(action, "ecr:") ||
        (statement.Effect == "Allow" && can(regex("^ecr:(Get|List|Describe|BatchGet|BatchCheck)", action)))
      ]])) &&
      anytrue([for statement in jsondecode(boundary.policy).Statement :
        statement.Effect == "Allow" && statement.Action == ["ecr:GetAuthorizationToken"] && statement.Resource == ["*"]
      ]) &&
      length(boundary.policy) <= 6144
    ])
    error_message = "Nodes must pull only the application and exact official add-on repositories in me-central-1, using registry 759879836304, without allowing ECR writes or exceeding IAM quota."
  }
}

run "node_pulls_official_addons_ap_south_2" {
  command = plan
  variables {
    aws_region        = "ap-south-2"
    state_kms_key_arn = "arn:aws:kms:ap-south-2:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition = alltrue([for boundary in values(aws_iam_policy.eks_node_boundary) :
      alltrue([for action in ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"] :
        toset(flatten([for statement in jsondecode(boundary.policy).Statement : statement.Resource if
          statement.Effect == "Allow" && contains(statement.Action, action) && !can(statement.Condition)
          ])) == toset([
          "arn:aws:ecr:ap-south-2:123456789012:repository/oficina-mecanica-api",
          "arn:aws:ecr:ap-south-2:900889452093:repository/amazon-k8s-cni",
          "arn:aws:ecr:ap-south-2:900889452093:repository/amazon-k8s-cni-init",
          "arn:aws:ecr:ap-south-2:900889452093:repository/amazon/aws-network-policy-agent",
          "arn:aws:ecr:ap-south-2:900889452093:repository/eks/coredns",
          "arn:aws:ecr:ap-south-2:900889452093:repository/eks/kube-proxy",
          "arn:aws:ecr:ap-south-2:900889452093:repository/eks/eks-pod-identity-agent",
          "arn:aws:ecr:ap-south-2:900889452093:repository/eks/aws-ebs-csi-driver",
          "arn:aws:ecr:ap-south-2:900889452093:repository/eks/csi-attacher",
          "arn:aws:ecr:ap-south-2:900889452093:repository/eks/csi-provisioner",
          "arn:aws:ecr:ap-south-2:900889452093:repository/eks/csi-resizer",
          "arn:aws:ecr:ap-south-2:900889452093:repository/eks/csi-snapshotter",
          "arn:aws:ecr:ap-south-2:900889452093:repository/eks/livenessprobe",
          "arn:aws:ecr:ap-south-2:900889452093:repository/eks/csi-node-driver-registrar",
          "arn:aws:ecr:ap-south-2:900889452093:repository/eks/volume-modifier-for-k8s",
        ])
      ]) &&
      alltrue([for statement in jsondecode(boundary.policy).Statement :
        statement.Effect != "Allow" || !anytrue([for resource in statement.Resource : strcontains(resource, ":900889452093:repository/")]) ||
        toset(statement.Action) == toset(["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"])
      ]) &&
      alltrue(flatten([for statement in jsondecode(boundary.policy).Statement : [for action in statement.Action :
        !startswith(action, "ecr:") ||
        (statement.Effect == "Allow" && can(regex("^ecr:(Get|List|Describe|BatchGet|BatchCheck)", action)))
      ]])) &&
      anytrue([for statement in jsondecode(boundary.policy).Statement :
        statement.Effect == "Allow" && statement.Action == ["ecr:GetAuthorizationToken"] && statement.Resource == ["*"]
      ]) &&
      length(boundary.policy) <= 6144
    ])
    error_message = "Nodes must pull only the application and exact official add-on repositories in ap-south-2, using registry 900889452093, without allowing ECR writes or exceeding IAM quota."
  }
}
