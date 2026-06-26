output "cluster_id" {
  value = aws_eks_cluster.this.id
}

output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  value       = local.oidc_issuer_host
  description = "OIDC issuer URL without https:// prefix, used in IAM condition keys"
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.this.arn
}

output "cluster_security_group_id" {
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  description = "EKS-managed security group (auto-created by EKS)"
}

output "additional_security_group_id" {
  value       = aws_security_group.cluster.id
  description = "Additional cluster security group managed by this module"
}

output "cluster_iam_role_arn" {
  value = aws_iam_role.cluster.arn
}
