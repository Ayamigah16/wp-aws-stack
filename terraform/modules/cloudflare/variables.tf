variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for DNS management"
  type        = string
}

variable "domain_name" {
  description = "Domain name for WordPress site"
  type        = string
}

variable "origin_ip" {
  description = "Origin server IP address"
  type        = string
}
