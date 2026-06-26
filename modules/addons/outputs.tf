output "alb_controller_status" {
  value = helm_release.aws_load_balancer_controller.status
}

output "cluster_autoscaler_status" {
  value = helm_release.cluster_autoscaler.status
}
