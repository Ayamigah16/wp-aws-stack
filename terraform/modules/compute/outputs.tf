output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.wordpress.id
}

output "instance_public_ip" {
  description = "EC2 public IP (EIP if enabled)"
  value       = var.enable_eip ? aws_eip.wordpress[0].public_ip : aws_instance.wordpress.public_ip
}

output "instance_private_ip" {
  description = "EC2 private IP"
  value       = aws_instance.wordpress.private_ip
}

output "ami_id" {
  description = "AMI ID used for instance"
  value       = data.aws_ami.ubuntu.id
}

output "eip_id" {
  description = "Elastic IP ID (if enabled)"
  value       = var.enable_eip ? aws_eip.wordpress[0].id : null
}

output "eip_public_ip" {
  description = "Elastic IP address (if enabled)"
  value       = var.enable_eip ? aws_eip.wordpress[0].public_ip : null
}
