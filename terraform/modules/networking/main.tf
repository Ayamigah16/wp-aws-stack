# VPC - Use default VPC for simplicity (production should use custom VPC)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Fetch Cloudflare IPv4 ranges for Security Group whitelist
data "http" "cloudflare_ipv4" {
  url = "https://www.cloudflare.com/ips-v4"
}

# Fetch Cloudflare IPv6 ranges
data "http" "cloudflare_ipv6" {
  url = "https://www.cloudflare.com/ips-v6"
}

locals {
  cloudflare_ipv4_ranges = split("\n", trimspace(data.http.cloudflare_ipv4.response_body))
  cloudflare_ipv6_ranges = split("\n", trimspace(data.http.cloudflare_ipv6.response_body))
}

# Security Group for WordPress EC2
resource "aws_security_group" "wordpress" {
  name_prefix = "${var.project_name}-"
  description = "Security group for WordPress EC2 - Cloudflare origin protection"
  vpc_id      = data.aws_vpc.default.id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-sg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# SSH Access - Restricted to specific IP
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.wordpress.id
  description       = "SSH access from allowed IPs only"
  
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
  cidr_ipv4   = var.ssh_allowed_cidr[0]

  tags = merge(
    var.tags,
    {
      Name = "ssh-restricted"
    }
  )
}

# HTTP Access - Cloudflare IPs only
resource "aws_vpc_security_group_ingress_rule" "http_cloudflare" {
  for_each = toset(local.cloudflare_ipv4_ranges)

  security_group_id = aws_security_group.wordpress.id
  description       = "HTTP from Cloudflare"
  
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
  cidr_ipv4   = each.value

  tags = merge(
    var.tags,
    {
      Name = "http-cloudflare"
    }
  )
}

# HTTPS Access - Cloudflare IPs only
resource "aws_vpc_security_group_ingress_rule" "https_cloudflare" {
  for_each = toset(local.cloudflare_ipv4_ranges)

  security_group_id = aws_security_group.wordpress.id
  description       = "HTTPS from Cloudflare"
  
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
  cidr_ipv4   = each.value

  tags = merge(
    var.tags,
    {
      Name = "https-cloudflare"
    }
  )
}

# Netdata monitoring access (optional, restricted)
resource "aws_vpc_security_group_ingress_rule" "netdata" {
  count = length(var.netdata_allowed_cidr) > 0 ? 1 : 0

  security_group_id = aws_security_group.wordpress.id
  description       = "Netdata monitoring dashboard"
  
  from_port   = 19999
  to_port     = 19999
  ip_protocol = "tcp"
  cidr_ipv4   = var.netdata_allowed_cidr[0]

  tags = merge(
    var.tags,
    {
      Name = "netdata-monitoring"
    }
  )
}

# Egress - Allow all outbound (required for updates, Cloudflare communication)
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.wordpress.id
  description       = "Allow all outbound traffic"
  
  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"

  tags = merge(
    var.tags,
    {
      Name = "all-outbound"
    }
  )
}
