output "security_group_id" {
  description = "ID of the WordPress security group"
  value       = aws_security_group.wordpress.id
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = data.aws_vpc.default.id
}

output "subnet_ids" {
  description = "List of subnet IDs"
  value       = data.aws_subnets.default.ids
}

output "cloudflare_ipv4_ranges" {
  description = "Cloudflare IPv4 ranges"
  value       = local.cloudflare_ipv4_ranges
}
