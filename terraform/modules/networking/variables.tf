variable "project_name" {
  description = "Project identifier for resource naming"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
}

variable "netdata_allowed_cidr" {
  description = "CIDR blocks allowed for Netdata dashboard access"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
