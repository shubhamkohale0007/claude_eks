output "node_iam_role_arn" {
  value = aws_iam_role.node.arn
}

output "node_iam_role_name" {
  value = aws_iam_role.node.name
}

output "node_security_group_id" {
  value = aws_security_group.node.id
}

output "autoscaling_group_name" {
  value = aws_autoscaling_group.this.name
}

output "launch_template_id" {
  value = aws_launch_template.this.id
}

output "launch_template_latest_version" {
  value = aws_launch_template.this.latest_version
}
