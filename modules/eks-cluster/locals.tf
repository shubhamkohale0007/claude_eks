locals {
  oidc_issuer_url = aws_eks_cluster.this.identity[0].oidc[0].issuer
  # Strip "https://" for use in IAM condition keys
  oidc_issuer_host = replace(local.oidc_issuer_url, "https://", "")
}
