variable "cluster_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "alb_controller_role_arn" {
  type = string
}

variable "cluster_autoscaler_role_arn" {
  type = string
}

variable "alb_controller_chart_version" {
  type    = string
  default = "1.8.1"
}

variable "cluster_autoscaler_chart_version" {
  type    = string
  default = "9.37.0"
}
