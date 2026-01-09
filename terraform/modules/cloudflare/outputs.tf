output "dns_record_id" {
  description = "Cloudflare DNS record ID"
  value       = cloudflare_record.wordpress.id
}

output "dns_record_name" {
  description = "Cloudflare DNS record name"
  value       = cloudflare_record.wordpress.name
}

output "dns_record_value" {
  description = "Cloudflare DNS record value (IP)"
  value       = cloudflare_record.wordpress.value
}

output "dns_record_proxied" {
  description = "Whether DNS record is proxied through Cloudflare"
  value       = cloudflare_record.wordpress.proxied
}
