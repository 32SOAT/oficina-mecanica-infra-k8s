locals {
  # Official private ECR registries for every supported commercial EKS region.
  # Never assume that an opt-in region uses the us-east-1 account.
  # https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html
  eks_addon_registry_accounts = {
    af-south-1     = "877085696533"
    ap-east-1      = "800184023465"
    ap-east-2      = "533267051163"
    ap-northeast-1 = "602401143452"
    ap-northeast-2 = "602401143452"
    ap-northeast-3 = "602401143452"
    ap-south-1     = "602401143452"
    ap-south-2     = "900889452093"
    ap-southeast-1 = "602401143452"
    ap-southeast-2 = "602401143452"
    ap-southeast-3 = "296578399912"
    ap-southeast-4 = "491585149902"
    ap-southeast-5 = "151610086707"
    ap-southeast-6 = "333609536671"
    ap-southeast-7 = "121268973566"
    ca-central-1   = "602401143452"
    ca-west-1      = "761377655185"
    eu-central-1   = "602401143452"
    eu-central-2   = "900612956339"
    eu-north-1     = "602401143452"
    eu-south-1     = "590381155156"
    eu-south-2     = "455263428931"
    eu-west-1      = "602401143452"
    eu-west-2      = "602401143452"
    eu-west-3      = "602401143452"
    il-central-1   = "066635153087"
    me-central-1   = "759879836304"
    me-south-1     = "558608220178"
    mx-central-1   = "730335286997"
    sa-east-1      = "602401143452"
    us-east-1      = "602401143452"
    us-east-2      = "602401143452"
    us-west-1      = "602401143452"
    us-west-2      = "602401143452"
  }

  # Includes init/sidecar containers; no repository or account wildcard.
  # EBS CSI pulls are supported here, but its installation and workload IAM
  # remain separate from the four add-ons currently installed by modules/eks.
  eks_addon_repositories = [
    "amazon-k8s-cni",
    "amazon-k8s-cni-init",
    "amazon/aws-network-policy-agent",
    "eks/coredns",
    "eks/kube-proxy",
    "eks/eks-pod-identity-agent",
    "eks/aws-ebs-csi-driver",
    "eks/csi-attacher",
    "eks/csi-provisioner",
    "eks/csi-resizer",
    "eks/csi-snapshotter",
    "eks/livenessprobe",
    "eks/csi-node-driver-registrar",
    "eks/volume-modifier-for-k8s",
  ]
  # An unmapped region is rejected by variable validation. The empty fallback
  # only prevents a secondary indexing diagnostic from obscuring that error.
  eks_addon_repository_arns = [for repository in local.eks_addon_repositories :
    "arn:aws:ecr:${var.aws_region}:${lookup(local.eks_addon_registry_accounts, var.aws_region, "")}:repository/${repository}"
  ]
}
