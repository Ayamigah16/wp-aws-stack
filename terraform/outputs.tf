###############################################################################
# Root Module Outputs
###############################################################################

output "instance_id" {
  description = "EC2 instance ID"
  value       = module.compute.instance_id
}

output "instance_public_ip" {
  description = "EC2 public IP (EIP if enabled)"
  value       = module.compute.instance_public_ip
}

output "instance_private_ip" {
  description = "EC2 private IP"
  value       = module.compute.instance_private_ip
}

output "security_group_id" {
  description = "Security Group ID"
  value       = module.networking.security_group_id
}

output "ssh_command" {
  description = "SSH connection command"
  value       = "ssh -i /path/to/private-key ubuntu@${module.compute.instance_public_ip}"
}

output "domain_name" {
  description = "WordPress domain name"
  value       = var.domain_name
}

output "wordpress_url" {
  description = "WordPress site URL (via Cloudflare)"
  value       = "https://${var.domain_name}"
}

output "netdata_url" {
  description = "Netdata monitoring dashboard URL (if enabled and accessible)"
  value       = var.enable_netdata && length(var.netdata_allowed_cidr) > 0 ? "http://${module.compute.instance_public_ip}:19999" : "Netdata not publicly accessible"
}

output "cloudflare_dns_record" {
  description = "Cloudflare DNS record details"
  value = {
    name    = module.cloudflare.dns_record_name
    value   = module.cloudflare.dns_record_value
    proxied = module.cloudflare.dns_record_proxied
  }
}

output "ami_id" {
  description = "AMI ID used for instance"
  value       = module.compute.ami_id
}

output "deployment_notes" {
  description = "Post-deployment notes"
  value = <<-EOT
    Deployment completed successfully!
    
    Next steps:
    1. Wait 5-10 minutes for user-data script to complete
    2. Check instance logs: sudo tail -f /var/log/cloud-init-output.log
    3. Verify WordPress: https://${var.domain_name}
    4. Complete WordPress installation via web UI
    5. Run validation: cd scripts && ./validate.sh
    
    Security:
    - Origin server only accessible via Cloudflare
    - SSH restricted to: ${join(", ", var.ssh_allowed_cidr)}
    - Database credentials stored in: /etc/wordpress-secrets.conf
    - SSL/TLS: Cloudflare Full (strict) mode
    
    Monitoring:
    - Netdata: ${var.enable_netdata && length(var.netdata_allowed_cidr) > 0 ? "http://${module.compute.instance_public_ip}:19999" : "Not publicly accessible"}
    - CloudWatch: Enhanced monitoring enabled
    - Logs: /var/log/apache2/, /var/log/mysql/, /var/www/html/wp-content/debug.log
    
    Backups:
    - Automated backups: ${var.enable_automated_backups ? "Enabled (daily via cron)" : "Disabled"}
    - Backup location: /var/backups/wordpress/
    - Retention: ${var.backup_retention_days} days
    
    Module Architecture:
    - Networking: Security Groups, VPC configuration
    - Compute: EC2 instance, IAM roles, EIP
    - Cloudflare: DNS, CDN, WAF, caching rules
  EOT
}
