# Security Documentation

## Security Posture Overview

This WordPress infrastructure implements **defense-in-depth** with multiple security layers, following AWS Well-Architected Framework and OWASP best practices.

## Threat Model

### Assets

1. **Critical**:
   - Database credentials (MySQL root, WordPress user)
   - SSH private keys
   - Cloudflare API tokens
   - WordPress admin accounts

2. **High Value**:
   - Customer data (if collecting)
   - WordPress content
   - Server compute resources

3. **Medium Value**:
   - Server logs
   - Backup files
   - Configuration files

### Threat Actors

1. **Automated Bots**:
   - Credential stuffing attacks
   - Vulnerability scanners
   - Content scrapers

2. **Opportunistic Attackers**:
   - Exploit known CVEs
   - Brute force attacks
   - Plugin vulnerability exploitation

3. **Targeted Attackers** (Lower probability):
   - APT groups
   - Competitors
   - Disgruntled users

### Attack Vectors

| Vector | Likelihood | Impact | Mitigation |
|--------|------------|--------|------------|
| WordPress brute force | High | Medium | Fail2ban, rate limiting |
| Plugin vulnerabilities | Medium | High | Auto-updates, monitoring |
| DDoS | Medium | High | Cloudflare protection |
| SQL injection | Low | High | Prepared statements, WAF |
| SSRF (IMDS) | Low | High | IMDSv2 enforcement |
| SSH brute force | Low | High | Key-only auth, IP restriction |

## Security Controls

### Layer 1: Edge Security (Cloudflare)

#### DDoS Protection

- **Unmetered DDoS mitigation**: Absorbs attacks at edge
- **Anycast network**: Distributes load across 200+ PoPs
- **Automatic detection**: No manual intervention required

#### Web Application Firewall (WAF)

**Enabled Rulesets**:
- Cloudflare Managed Ruleset (OWASP Top 10)
- WordPress-specific rules

**Configuration**:
```hcl
resource "cloudflare_ruleset" "wordpress_waf" {
  zone_id = var.cloudflare_zone_id
  kind    = "zone"
  phase   = "http_request_firewall_managed"
  
  rules {
    action = "execute"
    action_parameters {
      id = "efb7b8c949ac4650a09736fc376e9aee"  # Managed Ruleset
    }
  }
}
```

**Protected Against**:
- SQL Injection
- Cross-Site Scripting (XSS)
- Remote Code Execution (RCE)
- File Inclusion attacks
- Command Injection

#### Rate Limiting

**wp-login.php Protection**:
- **Threshold**: 5 requests per 60 seconds
- **Action**: CAPTCHA challenge
- **Duration**: 3600 seconds (1 hour)

**Rationale**: Prevents credential stuffing while allowing legitimate lockouts/retries.

**Limitation**: Cloudflare Free tier allows 1 rate limiting rule. Upgrade for additional rules (wp-admin, xmlrpc.php).

### Layer 2: Network Security (AWS)

#### Security Group Rules

**Ingress**:
```
SSH (22/tcp):     YOUR_IP/32 only
HTTP (80/tcp):    Cloudflare IP ranges only
HTTPS (443/tcp):  Cloudflare IP ranges only
Netdata (19999):  YOUR_IP/32 or disabled
```

**Egress**:
```
All traffic: 0.0.0.0/0 (required for updates, Cloudflare communication)
```

**Dynamic Cloudflare IP Updates**:
- Fetched via API at deployment: `https://www.cloudflare.com/ips-v4`
- Cron job updates Apache config monthly
- Prevents stale IP ranges

**Rationale**: Origin server completely hidden from direct internet access.

#### VPC Configuration

**Current**: Default VPC (acceptable for single instance)

**Production Hardening**:
```
Custom VPC:
- Public Subnet: EC2 instance (NAT gateway)
- Private Subnet: RDS database (when migrating)
- Network ACLs: Additional layer of defense
```

### Layer 3: Host Security (Ubuntu)

#### Firewall (UFW)

**Configuration**:
```bash
Default: Deny incoming, Allow outgoing
Allow: 22/tcp (SSH)
Allow: 80/tcp (HTTP)
Allow: 443/tcp (HTTPS)
Allow: 19999/tcp (Netdata, optional)
```

**Rationale**: Defense-in-depth redundancy with Security Group.

#### Intrusion Detection (Fail2ban)

**Monitored Services**:
1. **SSH** (sshd):
   - Max retries: 3
   - Ban time: 3600s (1 hour)
   - Find time: 600s (10 minutes)

2. **Apache Authentication** (apache-auth):
   - Max retries: 3
   - Ban time: 3600s

3. **WordPress** (custom filter):
   - Monitors: wp-login.php, xmlrpc.php
   - Max retries: 3
   - Ban time: 3600s

**Custom Filter** (`/etc/fail2ban/filter.d/wordpress.conf`):
```ini
[Definition]
failregex = ^<HOST> .* "POST .*wp-login.php
            ^<HOST> .* "POST .*xmlrpc.php
```

**Logs**: `/var/log/fail2ban.log`

**Unban Command**:
```bash
sudo fail2ban-client set wordpress unbanip <IP_ADDRESS>
```

#### SSH Hardening

**Disabled**:
- PasswordAuthentication
- PermitRootLogin
- X11Forwarding

**Enabled**:
- PubkeyAuthentication only
- MaxAuthTries: 3
- ClientAliveInterval: 300s (disconnect idle sessions)

**Key Management**:
- SSH key specified in `terraform.tfvars`
- Private key never stored on server
- Consider rotating keys annually

#### Automatic Updates

**Unattended Upgrades**:
- Security updates: Automatic installation
- Schedule: Daily
- Auto-reboot: Disabled (requires manual intervention)

**Configuration**: `/etc/apt/apt.conf.d/50unattended-upgrades`

**Monitoring**:
```bash
sudo cat /var/log/unattended-upgrades/unattended-upgrades.log
```

### Layer 4: Application Security (LAMP)

#### Apache Security

**Security Headers**:
```apache
Header set X-Content-Type-Options "nosniff"
Header set X-Frame-Options "SAMEORIGIN"
Header set X-XSS-Protection "1; mode=block"
Header set Referrer-Policy "strict-origin-when-cross-origin"
```

**Server Signature**: Disabled (prevents version disclosure)

**Directory Listing**: Disabled (`Options -Indexes`)

**Cloudflare Proxy Headers**:
```apache
RemoteIPHeader CF-Connecting-IP
RemoteIPTrustedProxy <Cloudflare IP ranges>
```

**Rationale**: Ensures real client IP is logged (not Cloudflare's proxy IP).

#### PHP Hardening

**Configuration** (`/etc/php/8.1/apache2/conf.d/99-wordpress-security.ini`):
```ini
expose_php = Off                    # Hide PHP version
display_errors = Off                # Don't expose errors to users
allow_url_include = Off             # Prevent remote file inclusion
session.cookie_httponly = 1         # Prevent XSS cookie theft
session.cookie_secure = 1           # HTTPS only cookies
session.use_strict_mode = 1         # Prevent session fixation
```

**Limits**:
```ini
max_execution_time = 60             # Prevent resource exhaustion
memory_limit = 256M                 # Balance functionality vs abuse
upload_max_filesize = 64M           # Reasonable for media uploads
```

#### MySQL Security

**Secure Installation**:
- Root password set (stored in `/etc/wordpress-secrets.conf`)
- Anonymous users removed
- Test database removed
- Remote root login disabled

**WordPress Database User**:
```sql
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, 
      CREATE TEMPORARY TABLES, LOCK TABLES 
ON wordpress.* TO 'wpuser'@'localhost';
```

**Rationale**: Least privilege principle. No GRANT, FILE, or SUPER privileges.

**Not Granted** (prevents escalation):
- FILE (prevents reading /etc/passwd)
- PROCESS (prevents viewing other queries)
- SUPER (prevents global changes)

### Layer 5: WordPress Hardening

#### wp-config.php Security

**Critical Settings**:
```php
define('DISALLOW_FILE_EDIT', true);       // Prevent theme/plugin editing via admin
define('FORCE_SSL_ADMIN', true);           // Require HTTPS for admin
define('WP_AUTO_UPDATE_CORE', 'minor');    // Auto-update security patches
define('WP_DEBUG_DISPLAY', false);         // Never show errors publicly
```

**Cloudflare HTTPS Detection**:
```php
if (isset($_SERVER['HTTP_CF_VISITOR'])) {
    $cf_visitor = json_decode($_SERVER['HTTP_CF_VISITOR']);
    if ($cf_visitor->scheme == 'https') {
        $_SERVER['HTTPS'] = 'on';
    }
}
```

**Rationale**: Prevents redirect loops with Cloudflare's Flexible SSL mode.

#### Authentication Salts

- Generated via WordPress API: `https://api.wordpress.org/secret-key/1.1/salt/`
- Unique per installation
- Rotate if credentials compromised

#### File Permissions

**Directories**: 755 (owner write, group/world read+execute)
**Files**: 644 (owner write, group/world read)
**wp-config.php**: 640 (owner read/write, group read only)

**Command**:
```bash
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;
chmod 640 /var/www/html/wp-config.php
```

#### Plugin/Theme Security

**Recommendations**:
- Install from official WordPress repository only
- Review ratings and recent updates before installing
- Delete unused plugins (don't just deactivate)
- Use [WPScan](https://wpscan.com/) for vulnerability scanning

**WP-CLI Usage**:
```bash
sudo -u www-data wp plugin list
sudo -u www-data wp plugin update --all
sudo -u www-data wp theme update --all
```

### Layer 6: Data Security

#### Secrets Management

**Storage**: `/etc/wordpress-secrets.conf`
```bash
# Permissions: 600 (root read/write only)
WP_DB_NAME="wordpress"
WP_DB_USER="wpuser"
WP_DB_PASSWORD="<generated-password>"
MYSQL_ROOT_PASSWORD="<generated-password>"
```

**Access**:
- Root only
- Sourced by backup scripts
- Never logged or displayed

**Rotation Procedure**:
```bash
# 1. Generate new password
NEW_PASS=$(openssl rand -base64 24)

# 2. Update MySQL
mysql -u root -p"$OLD_ROOT_PASS" -e "ALTER USER 'wpuser'@'localhost' IDENTIFIED BY '$NEW_PASS';"

# 3. Update wp-config.php
sudo sed -i "s/define( 'DB_PASSWORD', '.*' );/define( 'DB_PASSWORD', '$NEW_PASS' );/" /var/www/html/wp-config.php

# 4. Update secrets file
sudo sed -i "s/WP_DB_PASSWORD=.*/WP_DB_PASSWORD=\"$NEW_PASS\"/" /etc/wordpress-secrets.conf

# 5. Restart Apache
sudo systemctl restart apache2
```

#### Backup Encryption

**Current**: Backups stored locally, EBS volume encrypted at rest

**Enhancement** (Recommended for production):
```bash
# Encrypt backups before S3 upload
gpg --symmetric --cipher-algo AES256 backup.tar.gz

# Upload encrypted backup
aws s3 cp backup.tar.gz.gpg s3://bucket/backups/
```

#### Data at Rest

- **EBS Volumes**: Encrypted using AWS-managed keys
- **Snapshots**: Inherit encryption from source volume
- **MySQL**: InnoDB tablespace encryption (optional)

### Layer 7: Monitoring and Detection

#### Security Event Logging

**Locations**:
```
/var/log/fail2ban.log              # Intrusion detection
/var/log/apache2/wordpress_access.log  # All HTTP requests
/var/log/apache2/wordpress_error.log   # Application errors
/var/log/auth.log                  # SSH authentication attempts
/var/www/html/wp-content/debug.log # WordPress errors (if WP_DEBUG=true)
```

**Log Retention**: 14 days (via logrotate)

**Monitoring**:
```bash
# Failed SSH attempts
sudo grep "Failed password" /var/log/auth.log | tail -20

# Fail2ban active bans
sudo fail2ban-client status wordpress

# Recent Apache errors
sudo tail -50 /var/log/apache2/wordpress_error.log
```

#### Anomaly Detection

**Netdata Alarms** (requires configuration):
- CPU usage > 90% for 10 minutes
- Disk usage > 90%
- Apache 5xx error rate > 10/minute
- MySQL connection failures

**CloudWatch Alarms** (not implemented, recommended):
- EC2 StatusCheckFailed
- High network traffic (potential DDoS)
- Disk space critical

## Incident Response

### Security Breach Procedure

**Phase 1: Containment**
```bash
# 1. Isolate instance (block all traffic)
aws ec2 modify-instance-attribute --instance-id <ID> \
  --groups sg-emergency-lockdown

# 2. Create forensic snapshot
aws ec2 create-snapshot --volume-id <VOL_ID> \
  --description "Forensic-$(date +%Y%m%d)"

# 3. Preserve logs
sudo tar -czf /tmp/logs-$(date +%Y%m%d).tar.gz /var/log
```

**Phase 2: Analysis**
```bash
# Check for backdoors
sudo find /var/www/html -name "*.php" -mtime -7
sudo grep -r "eval(base64_decode" /var/www/html/

# Check for modified files
sudo debsums -c  # Verify package file integrity

# Review recent logins
sudo last -20
sudo lastb -20  # Failed logins
```

**Phase 3: Recovery**
```bash
# Restore from known-good backup
sudo /usr/local/bin/wordpress-restore.sh <TIMESTAMP>

# Rotate all credentials
# See "Secrets Management" section above

# Rebuild instance if compromised
cd terraform
terraform destroy -target=aws_instance.wordpress
terraform apply
```

**Phase 4: Post-Incident**
- Document timeline and root cause
- Update security controls
- Notify users if data breach occurred (GDPR requirement)

### Credential Compromise

**WordPress Admin**:
1. SSH to server
2. Reset via WP-CLI: `sudo -u www-data wp user update admin --user_pass=<new_pass>`
3. Review recent admin actions in WordPress activity logs

**SSH Key**:
1. Access via AWS Systems Manager Session Manager (if configured)
2. Update authorized_keys: `vim ~/.ssh/authorized_keys`
3. Alternatively, stop instance, detach EBS, mount on new instance

**Cloudflare API Token**:
1. Revoke token in Cloudflare dashboard
2. Generate new token
3. Update `terraform.tfvars` and re-run `terraform apply`

## Compliance

### GDPR Requirements

| Requirement | Implementation | Status |
|-------------|----------------|--------|
| Data encryption at rest | EBS encryption | ✅ Implemented |
| Data encryption in transit | TLS 1.2+ | ✅ Implemented |
| Right to access | WordPress export | ✅ Built-in |
| Right to erasure | Manual user deletion | ⚠️ Manual process |
| Data breach notification | Manual | ⚠️ Requires procedure |

**Gap**: Automated PII detection and user data export. Consider plugins like WP GDPR Compliance.

### Security Audit Checklist

**Monthly**:
- [ ] Review fail2ban logs for patterns
- [ ] Check for outdated plugins: `wp plugin list`
- [ ] Verify backups completed successfully
- [ ] Review WordPress user list for unauthorized accounts

**Quarterly**:
- [ ] Update Cloudflare IP ranges: `/usr/local/bin/update-cloudflare-ips.sh`
- [ ] Rotate database credentials
- [ ] Run WPScan vulnerability scan
- [ ] Review and update firewall rules

**Annually**:
- [ ] Penetration testing (use OWASP ZAP or hire professional)
- [ ] Security group audit
- [ ] Review IAM roles and policies
- [ ] SSH key rotation

## Known Limitations

1. **No Web Application Firewall on Origin**: Cloudflare WAF only protects proxied traffic. Direct IP access bypassed WAF before Security Group blocking was implemented.

2. **Single Point of Failure**: No high availability. Mitigated by:
   - Automated backups
   - Infrastructure as Code (quick rebuild)
   - Elastic IP (static endpoint)

3. **Shared Hosting Environment**: WordPress and database on same instance. Compromise of Apache could expose database.

4. **No Intrusion Detection System (IDS)**: Fail2ban provides basic protection but not full IDS. Consider AIDE or Wazuh for file integrity monitoring.

5. **Cloudflare Free Tier**: Limited rate limiting rules, no custom WAF rules.

## Security Roadmap

**Short Term** (1-3 months):
- Implement CloudWatch Alarms for critical metrics
- Configure AIDE for file integrity monitoring
- Add Cloudflare Access for admin area (zero-trust)

**Medium Term** (3-6 months):
- Migrate to RDS with encryption at rest
- Implement AWS WAF on ALB (for non-Cloudflare traffic)
- Add AWS GuardDuty for threat detection

**Long Term** (6-12 months):
- Multi-region deployment with failover
- Implement AWS Certificate Manager for origin certificates
- Add AWS Security Hub for centralized security monitoring

---

**Document Version**: 1.0  
**Last Updated**: January 2026  
**Next Review**: April 2026
