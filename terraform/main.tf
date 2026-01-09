###############################################################################
# Root Module - WordPress AWS Stack
# Purpose: Orchestrates all modules for complete infrastructure deployment
###############################################################################

locals {
  common_tags = {
    Project     = "WordPress-AWS-Stack"
    ManagedBy   = "Terraform"
    Environment = var.environment
    Owner       = var.owner_email
  }
}

# Networking Module - Security Groups and VPC
module "networking" {
  source = "./modules/networking"

  project_name         = var.project_name
  ssh_allowed_cidr     = var.ssh_allowed_cidr
  netdata_allowed_cidr = var.netdata_allowed_cidr
  tags                 = local.common_tags
}

# Compute Module - EC2, IAM, EIP
module "compute" {
  source = "./modules/compute"

  project_name            = var.project_name
  instance_type           = var.instance_type
  ami_filter              = var.ami_filter
  ami_owner               = var.ami_owner
  root_volume_size        = var.root_volume_size
  enable_eip              = var.enable_eip
  ssh_public_key          = var.ssh_public_key
  security_group_id       = module.networking.security_group_id
  subnet_id               = module.networking.subnet_ids[0]
  wp_db_name              = var.wp_db_name
  wp_db_user              = var.wp_db_user
  wp_db_password          = var.wp_db_password
  mysql_root_password     = var.mysql_root_password
  domain_name             = var.domain_name
  enable_netdata          = var.enable_netdata
  enable_automated_backups = var.enable_automated_backups
  backup_retention_days   = var.backup_retention_days
  tags                    = local.common_tags
}

# Cloudflare Module - DNS, CDN, WAF
module "cloudflare" {
  source = "./modules/cloudflare"

  cloudflare_zone_id = var.cloudflare_zone_id
  domain_name        = var.domain_name
  origin_ip          = module.compute.instance_public_ip
}
