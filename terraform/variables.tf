variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "owner_email" {
  description = "Email of infrastructure owner"
  type        = string
}

variable "project_name" {
  description = "Project identifier"
  type        = string
  default     = "wordpress-stack"
}

variable "terraform_state_bucket" {
  description = "S3 bucket name for Terraform state (must be globally unique)"
  type        = string
  default     = "wp-terraform-state-wordpress-stack"
}

variable "terraform_state_dynamodb_table" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "terraform-state-lock-wp"
}

# EC2 Configuration
variable "instance_type" {
  description = "EC2 instance type (t3.small recommended minimum for production)"
  type        = string
  default     = "t3.small"
}

variable "ami_filter" {
  description = "AMI filter for Ubuntu LTS"
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "ami_owner" {
  description = "Canonical's AWS account ID"
  type        = string
  default     = "099720109477"
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
  default     = 30
}

variable "enable_eip" {
  description = "Whether to allocate and associate Elastic IP"
  type        = bool
  default     = true
}

# Security Configuration
variable "ssh_allowed_cidr" {
  description = "CIDR blocks allowed for SSH access (restrict to your IP)"
  type        = list(string)
  validation {
    condition     = length(var.ssh_allowed_cidr) > 0
    error_message = "SSH access must be restricted to specific IPs"
  }
}

variable "ssh_public_key" {
  description = "SSH public key for EC2 access"
  type        = string
  sensitive   = true
}

# WordPress Configuration
variable "wp_db_name" {
  description = "WordPress database name"
  type        = string
  default     = "wordpress"
}

variable "wp_db_user" {
  description = "WordPress database username"
  type        = string
  default     = "wpuser"
}

variable "wp_db_password" {
  description = "WordPress database password (min 16 chars, alphanumeric + special)"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.wp_db_password) >= 16
    error_message = "Database password must be at least 16 characters"
  }
}

variable "mysql_root_password" {
  description = "MySQL root password"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.mysql_root_password) >= 16
    error_message = "Root password must be at least 16 characters"
  }
}

# Cloudflare Configuration
variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:Edit permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for DNS management"
  type        = string
}

variable "domain_name" {
  description = "Domain name for WordPress site (e.g., example.com or www.example.com)"
  type        = string
}

# Monitoring
variable "enable_netdata" {
  description = "Install and configure Netdata monitoring"
  type        = bool
  default     = true
}

variable "netdata_allowed_cidr" {
  description = "CIDR blocks allowed for Netdata dashboard access"
  type        = list(string)
  default     = []
}

# Backup Configuration
variable "enable_automated_backups" {
  description = "Enable automated backup script via cron"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 7
}
