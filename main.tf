locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = var.cluster_name
  }
}

module "vpc" {
  source = "./modules/vpc"

  vpc_cidr             = var.vpc_cidr
  cluster_name         = var.cluster_name
  environment          = var.environment
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  enable_vpc_endpoints = true
  tags                 = local.common_tags
}

# Phase 1: terraform apply -target=module.vpc -target=module.eks_cluster
# Phase 2: terraform apply
module "eks_cluster" {
  source = "./modules/eks-cluster"

  cluster_name       = var.cluster_name
  cluster_version    = var.cluster_version
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  endpoint_public_access           = var.endpoint_public_access
  public_access_cidrs              = var.public_access_cidrs
  enabled_log_types                = ["api", "audit", "authenticator"]

  coredns_version                  = var.coredns_version
  kube_proxy_version               = var.kube_proxy_version
  vpc_cni_version                  = var.vpc_cni_version
  vpc_cni_service_account_role_arn = module.irsa_vpc_cni.role_arn

  tags = local.common_tags
}

module "irsa_vpc_cni" {
  source = "./modules/irsa"

  role_name            = "${var.cluster_name}-vpc-cni"
  oidc_provider_arn    = module.eks_cluster.oidc_provider_arn
  oidc_provider_url    = module.eks_cluster.cluster_oidc_issuer_url
  namespace            = "kube-system"
  service_account_name = "aws-node"
  policy_arns          = ["arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"]
  tags                 = local.common_tags

  depends_on = [module.eks_cluster]
}

module "node_group" {
  source = "./modules/self-managed-node-group"

  cluster_name                       = module.eks_cluster.cluster_name
  cluster_version                    = var.cluster_version
  cluster_endpoint                   = module.eks_cluster.cluster_endpoint
  cluster_certificate_authority_data = module.eks_cluster.cluster_certificate_authority_data

  node_group_name = "general"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  instance_type   = var.node_instance_type
  disk_size       = var.node_disk_size
  min_size        = var.node_min_size
  max_size        = var.node_max_size
  desired_size    = var.node_desired_size

  node_labels = "role=general,env=${var.environment}"
  tags        = local.common_tags
}

resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode([{
      rolearn  = module.node_group.node_iam_role_arn
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    }])
  }

  force = true

  depends_on = [module.eks_cluster, module.node_group]
}

module "irsa_alb_controller" {
  source = "./modules/irsa"

  role_name            = "${var.cluster_name}-alb-controller"
  oidc_provider_arn    = module.eks_cluster.oidc_provider_arn
  oidc_provider_url    = module.eks_cluster.cluster_oidc_issuer_url
  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"
  inline_policy_json   = data.aws_iam_policy_document.alb_controller.json
  tags                 = local.common_tags

  depends_on = [module.eks_cluster]
}

module "irsa_cluster_autoscaler" {
  source = "./modules/irsa"

  role_name            = "${var.cluster_name}-cluster-autoscaler"
  oidc_provider_arn    = module.eks_cluster.oidc_provider_arn
  oidc_provider_url    = module.eks_cluster.cluster_oidc_issuer_url
  namespace            = "kube-system"
  service_account_name = "cluster-autoscaler"
  inline_policy_json   = data.aws_iam_policy_document.cluster_autoscaler.json
  tags                 = local.common_tags

  depends_on = [module.eks_cluster]
}

module "addons" {
  source = "./modules/addons"

  cluster_name                     = module.eks_cluster.cluster_name
  aws_region                       = var.aws_region
  vpc_id                           = module.vpc.vpc_id
  alb_controller_role_arn          = module.irsa_alb_controller.role_arn
  cluster_autoscaler_role_arn      = module.irsa_cluster_autoscaler.role_arn
  alb_controller_chart_version     = var.alb_controller_chart_version
  cluster_autoscaler_chart_version = var.cluster_autoscaler_chart_version

  depends_on = [
    module.node_group,
    kubernetes_config_map_v1_data.aws_auth,
    module.irsa_alb_controller,
    module.irsa_cluster_autoscaler,
  ]
}

# ── IAM policy documents ────────────────────────────────────────────────────────

data "aws_iam_policy_document" "alb_controller" {
  statement {
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeCoipPools",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "cognito-idp:DescribeUserPoolClient",
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:ListResourcesForWebACL",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:DeleteSecurityGroup",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:SetWebAcl",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:ModifyRule",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements",
      "eks:DescribeNodegroup",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"
      values   = ["true"]
    }
    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${var.cluster_name}"
      values   = ["owned"]
    }
  }
}
