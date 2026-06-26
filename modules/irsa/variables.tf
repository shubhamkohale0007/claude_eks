variable "role_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type        = string
  description = "OIDC issuer URL without https:// prefix"
}

variable "namespace" {
  type = string
}

variable "service_account_name" {
  type = string
}

variable "policy_arns" {
  type    = list(string)
  default = []
  description = "List of managed IAM policy ARNs to attach"
}

variable "inline_policy_json" {
  type        = string
  default     = null
  description = "Optional inline policy JSON document"
}

variable "tags" {
  type    = map(string)
  default = {}
}
