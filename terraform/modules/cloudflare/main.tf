# Cloudflare DNS Record
resource "cloudflare_record" "wordpress" {
  zone_id = var.cloudflare_zone_id
  name    = var.domain_name
  value   = var.origin_ip
  type    = "A"
  ttl     = 1  # Automatic TTL when proxied
  proxied = true  # Enable Cloudflare proxy (orange cloud)

  comment = "Managed by Terraform - WordPress origin server"
}

# Cloudflare Zone Settings - SSL/TLS
resource "cloudflare_zone_settings_override" "wordpress" {
  zone_id = var.cloudflare_zone_id

  settings {
    # SSL/TLS Configuration
    ssl = "strict"  # Full (strict) - requires valid cert on origin
    always_use_https = "on"
    min_tls_version = "1.2"
    tls_1_3 = "on"
    automatic_https_rewrites = "on"

    # Security Settings
    security_level = "medium"
    challenge_ttl = 1800
    browser_check = "on"

    # Performance
    brotli = "on"
    minify {
      css  = "on"
      js   = "on"
      html = "on"
    }

    # Caching
    browser_cache_ttl = 14400
    cache_level = "aggressive"
  }
}

# Cloudflare WAF Managed Rules (Free tier)
resource "cloudflare_ruleset" "wordpress_waf" {
  zone_id     = var.cloudflare_zone_id
  name        = "WordPress Protection"
  description = "Managed WAF rules for WordPress"
  kind        = "zone"
  phase       = "http_request_firewall_managed"

  rules {
    action = "execute"
    action_parameters {
      id = "efb7b8c949ac4650a09736fc376e9aee"  # Cloudflare Managed Ruleset
    }
    expression = "true"
    enabled    = true
  }
}

# Rate Limiting for wp-login.php (Free tier has limitations)
resource "cloudflare_rate_limit" "wp_login" {
  zone_id = var.cloudflare_zone_id
  
  threshold = 5
  period    = 60
  
  match {
    request {
      url_pattern = "*/wp-login.php*"
    }
  }
  
  action {
    mode    = "challenge"
    timeout = 3600
  }

  description = "Rate limit WordPress login attempts"
  bypass {
    name  = "url"
    value = "api.example.com/*"
  }
}

# Cache Rules - Bypass admin areas
resource "cloudflare_page_rule" "bypass_admin" {
  zone_id  = var.cloudflare_zone_id
  target   = "*${var.domain_name}/wp-admin*"
  priority = 1

  actions {
    cache_level = "bypass"
  }
}

resource "cloudflare_page_rule" "bypass_login" {
  zone_id  = var.cloudflare_zone_id
  target   = "*${var.domain_name}/wp-login.php*"
  priority = 2

  actions {
    cache_level = "bypass"
    security_level = "high"
  }
}

# Cache static assets aggressively
resource "cloudflare_page_rule" "cache_static" {
  zone_id  = var.cloudflare_zone_id
  target   = "*${var.domain_name}/*.{jpg,jpeg,png,gif,ico,css,js,svg,woff,woff2,ttf,eot}"
  priority = 3

  actions {
    cache_level = "cache_everything"
    edge_cache_ttl = 2592000  # 30 days
  }
}
