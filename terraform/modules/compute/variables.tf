variable "project_name" {
  description = "Project identifier for resource naming"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "ami_filter" {
  description = "AMI filter for Ubuntu LTS"
  type        = string
}

variable "ami_owner" {
  description = "Canonical's AWS account ID"
  type        = string
}

variable "root_volume_size" {
  description = "Root volume size in GB"
  type        = number
}

variable "enable_eip" {
  description = "Whether to allocate and associate Elastic IP"
  type        = bool
}

variable "ssh_public_key" {
  description = "SSH public key for EC2 access"
  type        = string
  sensitive   = true
}

variable "security_group_id" {
  description = "Security group ID to attach to instance"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for instance placement"
  type        = string
}

variable "wp_db_name" {
  description = "WordPress database name"
  type        = string
}

variable "wp_db_user" {
  description = "WordPress database username"
  type        = string
}

variable "wp_db_password" {
  description = "WordPress database password"
  type        = string
  sensitive   = true
}

variable "mysql_root_password" {
  description = "MySQL root password"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Domain name for WordPress site"
  type        = string
}

variable "enable_netdata" {
  description = "Install and configure Netdata monitoring"
  type        = bool
}

variable "enable_automated_backups" {
  description = "Enable automated backup script via cron"
  type        = bool
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
