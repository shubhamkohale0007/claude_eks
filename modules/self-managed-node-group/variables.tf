variable "cluster_name" {
  type = string
}

variable "cluster_version" {
  type = string
}

variable "cluster_endpoint" {
  type = string
}

variable "cluster_certificate_authority_data" {
  type = string
}

variable "node_group_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "instance_type" {
  type    = string
  default = "m5.large"
}

variable "disk_size" {
  type    = number
  default = 50
}

variable "min_size" {
  type = number
}

variable "max_size" {
  type = number
}

variable "desired_size" {
  type = number
}

variable "additional_security_group_ids" {
  type    = list(string)
  default = []
}

variable "node_labels" {
  type    = string
  default = ""
  description = "Comma-separated kubelet node labels, e.g. role=worker,env=dev"
}

variable "node_taints" {
  type    = string
  default = ""
  description = "Comma-separated kubelet taints, e.g. key=val:NoSchedule"
}

variable "tags" {
  type    = map(string)
  default = {}
}
