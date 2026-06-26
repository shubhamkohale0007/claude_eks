output "cluster_name" {
  value = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.eks_cluster.cluster_endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "node_iam_role_arn" {
  value = module.node_group.node_iam_role_arn
}

output "oidc_provider_arn" {
  value = module.eks_cluster.oidc_provider_arn
}
