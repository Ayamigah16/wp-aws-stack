# WordPress on AWS - Production Infrastructure

[![Infrastructure](https://img.shields.io/badge/Infrastructure-Terraform-623CE4)](https://www.terraform.io/)
[![Automation](https://img.shields.io/badge/Automation-Ansible-EE0000)](https://www.ansible.com/)
[![CDN](https://img.shields.io/badge/CDN-Cloudflare-F38020)](https://www.cloudflare.com/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

Production-ready, fully automated WordPress deployment on AWS with Cloudflare CDN, comprehensive security hardening, monitoring, and operational excellence.

## 🎯 Project Overview

Self-hosted WordPress platform designed for production workloads with enterprise-grade security, performance, and observability. Implements Infrastructure as Code (IaC) principles with idempotent automation.

### Key Features

- **Full Infrastructure Automation**: Terraform-managed AWS resources
- **Configuration Management**: Ansible playbooks for repeatable deployments
- **Origin Protection**: Cloudflare CDN with WAF and DDoS protection
- **Security Hardening**: Multi-layer security (UFW, fail2ban, SSH hardening)
- **Monitoring**: Netdata real-time metrics for Apache, MySQL, and system resources
- **Automated Backups**: Daily database and file backups with configurable retention
- **SSL/TLS**: Cloudflare Full (strict) mode with automatic certificate management
- **High Availability Ready**: EIP allocation, monitoring, and recovery procedures

## 🏗️ Architecture

```
Internet Users
       ↓
[Cloudflare CDN/WAF]
    (DDoS Protection, Rate Limiting, Caching)
       ↓
[AWS Security Group]
    (Cloudflare IPs only: 80/443)
    (Restricted SSH: Your IP only)
       ↓
[EC2 Ubuntu 22.04 LTS]
    ├── UFW Firewall
    ├── Fail2ban (Brute Force Protection)
    ├── Apache 2.4 (HTTPS-aware via X-Forwarded-Proto)
    ├── PHP 8.1 (Hardened configuration)
    ├── MySQL 8.0 (Dedicated WP user, least privilege)
    ├── WordPress (Latest, security-hardened)
    ├── Netdata (Real-time monitoring)
    └── Automated Backups (Cron)
```

### Network Flow

1. User requests → Cloudflare edge (200+ global PoPs)
2. Cloudflare applies WAF rules, caching, rate limiting
3. Origin request sent to AWS EC2 via Cloudflare IPs only
4. Apache validates proxy headers, processes request
5. WordPress responds with appropriate caching headers
6. Cloudflare caches static assets (30 days), bypasses admin

## 📋 Prerequisites

### Required Tools

- **Terraform** >= 1.5.0
- **Ansible** >= 2.14
- **AWS CLI** >= 2.0 (configured with credentials)
- **SSH** client
- **curl**, **dig**, **nc** (for validation)

### AWS Requirements

- AWS Account with programmatic access
- IAM user with EC2, VPC, EIP permissions
- Default VPC (or custom VPC configuration)
- SSH key pair generated

### Cloudflare Requirements

- Cloudflare account (Free tier sufficient)
- Domain added to Cloudflare
- API Token with Zone:Edit permissions
- Zone ID

## 🚀 Quick Start

### 1. Clone and Configure

```bash
git clone <repository-url>
cd wp-aws-stack

# Configure Terraform variables
cd terraform
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

### 2. Configure Secrets

Generate strong passwords:

```bash
openssl rand -base64 24  # For wp_db_password
openssl rand -base64 24  # For mysql_root_password
```

Edit `terraform.tfvars`:

```hcl
aws_region           = "us-east-1"
owner_email          = "your-email@example.com"
instance_type        = "t3.small"
ssh_allowed_cidr     = ["YOUR_IP/32"]
ssh_public_key       = "ssh-rsa AAAAB3..."
wp_db_password       = "generated-password-here"
mysql_root_password  = "generated-password-here"
cloudflare_api_token = "your-cloudflare-token"
cloudflare_zone_id   = "your-zone-id"
domain_name          = "example.com"
enable_netdata       = true
enable_automated_backups = true
```

### 3. Deploy Infrastructure

```bash
cd scripts
chmod +x *.sh
./deploy.sh
```

This will:
- Initialize Terraform
- Validate configuration
- Show execution plan
- Prompt for confirmation
- Deploy all AWS resources
- Configure Cloudflare DNS and CDN
- Bootstrap EC2 with LAMP stack

### 4. Wait for Bootstrap

EC2 user-data script takes 5-10 minutes. Monitor progress:

```bash
./ssh-connect.sh
sudo tail -f /var/log/cloud-init-output.log
```

### 5. Validate Deployment

```bash
cd scripts
./validate.sh <EC2_IP> <DOMAIN_NAME>
```

Expected output: All tests passing, 0 critical failures.

### 6. Complete WordPress Setup

Visit `https://your-domain.com` and complete the 5-minute WordPress installation:
- Select language
- Create admin user
- Set site title

## 🔒 Security Architecture

### Defense in Depth

1. **Network Layer**
   - Security Group: Cloudflare IPs only for HTTP/HTTPS
   - UFW: Host-level firewall
   - SSH: Restricted to specific CIDR

2. **Application Layer**
   - Fail2ban: Brute force protection (wp-login.php, xmlrpc.php)
   - Cloudflare WAF: OWASP Top 10 protection
   - Rate Limiting: 5 requests/60s on login endpoint
   - Disallow file editing in wp-admin

3. **Transport Layer**
   - TLS 1.2+ only
   - Cloudflare Full (strict) mode
   - HSTS enabled
   - Force SSL for wp-admin

4. **Data Layer**
   - MySQL: Least privilege user
   - Secrets stored in `/etc/wordpress-secrets.conf` (600 permissions)
   - Database backups encrypted at rest (EBS encryption)

### Key Security Decisions

| Decision | Rationale | Tradeoff |
|----------|-----------|----------|
| Cloudflare IPs only | Prevent direct origin access, reduce attack surface | Dependency on Cloudflare; failover complexity |
| IMDSv2 enforcement | Prevent SSRF attacks on metadata service | None (best practice) |
| No EIP by default | Cost optimization | IP change on instance replacement |
| SSH key only | Prevent password-based attacks | Key management responsibility |
| Fail2ban enabled | Automatic threat response | Potential for false positives |

## 📊 Monitoring and Observability

### Netdata Dashboard

Real-time metrics accessible at `http://<EC2_IP>:19999` (if allowed):

- **System**: CPU, RAM, disk I/O, network
- **Apache**: Requests/s, bandwidth, worker status
- **MySQL**: Queries, connections, slow queries
- **PHP**: Process count, memory usage

### Log Locations

```
/var/log/apache2/wordpress_access.log  # Web server access
/var/log/apache2/wordpress_error.log   # Apache errors
/var/log/mysql/error.log               # MySQL errors
/var/www/html/wp-content/debug.log     # WordPress debug (if enabled)
/var/log/wordpress-backup.log          # Backup operations
/var/log/fail2ban.log                  # Security events
```

### Health Checks

```bash
# Remote health check
./scripts/remote-health-check.sh <EC2_IP>

# Manual checks
ssh ubuntu@<EC2_IP>
sudo systemctl status apache2 mysql fail2ban netdata
sudo fail2ban-client status
sudo ufw status
```

## 💾 Backup and Recovery

### Automated Backups

- **Schedule**: Daily at 2:00 AM UTC
- **Retention**: 7 days (configurable)
- **Location**: `/var/backups/wordpress/`
- **Contents**:
  - MySQL dump (compressed): `db_TIMESTAMP.sql.gz`
  - WordPress files (compressed): `files_TIMESTAMP.tar.gz`

### Manual Backup

```bash
ssh ubuntu@<EC2_IP>
sudo /usr/local/bin/wordpress-backup.sh
```

### Restore Procedure

```bash
# List available backups
ssh ubuntu@<EC2_IP>
ls -lh /var/backups/wordpress/

# Restore specific backup
sudo /usr/local/bin/wordpress-restore.sh 20260109_020000

# Verify restoration
curl -I https://your-domain.com
```

### Disaster Recovery

1. **Complete instance failure**:
   ```bash
   cd terraform
   terraform destroy -target=aws_instance.wordpress
   terraform apply  # Recreates instance with EIP
   ```

2. **Database corruption**:
   - Restore from latest backup
   - Verify data integrity
   - Clear Cloudflare cache

3. **Security breach**:
   - Isolate instance (modify security group)
   - Create forensic snapshot
   - Restore from known-good backup
   - Rotate all credentials

## 🔧 Operational Procedures

### Scaling Considerations

**Vertical Scaling** (Increase instance size):
```bash
cd terraform
# Edit terraform.tfvars: instance_type = "t3.medium"
terraform apply
```

**Horizontal Scaling** (Not implemented, requires):
- Application Load Balancer
- RDS for shared database
- EFS/S3 for shared uploads
- Redis for session management

### Updating WordPress

```bash
ssh ubuntu@<EC2_IP>
cd /var/www/html
sudo -u www-data wp core update
sudo -u www-data wp plugin update --all
sudo -u www-data wp theme update --all
```

### SSL Certificate Management

Cloudflare handles SSL termination. For origin certificates:

1. **Cloudflare Origin Certificate** (15-year validity):
   - Generate in Cloudflare dashboard
   - Install on EC2: `/etc/ssl/cloudflare/`
   - Configure Apache VirtualHost

2. **Let's Encrypt** (90-day renewal):
   ```bash
   sudo certbot --apache -d your-domain.com
   ```

### Performance Tuning

**PHP Optimization**:
- Edit `/etc/php/8.1/apache2/conf.d/99-wordpress-security.ini`
- Increase `memory_limit`, `max_execution_time` as needed
- Restart Apache: `sudo systemctl restart apache2`

**MySQL Optimization**:
- Edit `/etc/mysql/mysql.conf.d/mysqld.cnf`
- Adjust `innodb_buffer_pool_size` (50-70% of RAM)
- Restart MySQL: `sudo systemctl restart mysql`

**Apache Optimization**:
- Enable HTTP/2: `sudo a2enmod http2`
- Configure MPM event for better concurrency
- Enable Brotli compression

### Cost Optimization

| Resource | Monthly Cost (approx) | Optimization |
|----------|----------------------|--------------|
| t3.small EC2 | ~$15 | Reserved Instance: -40% |
| EBS 30GB gp3 | ~$2.40 | Snapshot lifecycle policy |
| Data Transfer | Variable | Cloudflare caches ~80% |
| EIP | $0 (attached) | Release if not needed |
| **Total** | **~$17-20** | RI: ~$12/month |

## 📚 Additional Documentation

- [ARCHITECTURE.md](docs/ARCHITECTURE.md) - Deep dive into design decisions
- [SECURITY.md](docs/SECURITY.md) - Threat model and security controls
- [OPERATIONS.md](docs/OPERATIONS.md) - Runbooks and troubleshooting
- [Terraform Outputs](terraform/outputs.tf) - Infrastructure details

## 🧪 Testing

### Local Testing (Terraform)

```bash
cd terraform
terraform plan  # Dry run
terraform validate  # Syntax check
terraform fmt -check  # Style check
```

### Integration Testing

```bash
cd scripts
./validate.sh <EC2_IP> <DOMAIN_NAME>
```

Validates:
- DNS resolution via Cloudflare
- HTTPS configuration
- Security headers
- Origin protection
- WordPress functionality
- Cache rules
- Rate limiting
- Performance metrics

## 🔄 CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy WordPress Infrastructure

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: hashicorp/setup-terraform@v2
      - name: Terraform Init
        run: cd terraform && terraform init
      - name: Terraform Apply
        run: cd terraform && terraform apply -auto-approve
        env:
          TF_VAR_cloudflare_api_token: ${{ secrets.CF_API_TOKEN }}
          TF_VAR_wp_db_password: ${{ secrets.WP_DB_PASSWORD }}
```

## 🐛 Troubleshooting

### Common Issues

**WordPress redirect loop**:
```bash
# Verify Cloudflare proxy headers in wp-config.php
ssh ubuntu@<EC2_IP>
grep -A 5 "HTTP_CF_VISITOR" /var/www/html/wp-config.php
```

**502 Bad Gateway**:
```bash
# Check Apache/MySQL status
sudo systemctl status apache2 mysql
# Check error logs
sudo tail -50 /var/log/apache2/wordpress_error.log
```

**Direct IP access working** (should be blocked):
```bash
# Verify Apache config
sudo apache2ctl -S | grep "ServerName"
# Check Security Group rules
aws ec2 describe-security-groups --group-ids <SG_ID>
```

### Debug Mode

Enable WordPress debugging:
```php
// In wp-config.php
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);
```

## 📝 Resume Highlights

Perfect for DevOps portfolios:

- ✅ **Infrastructure as Code**: Terraform with modular design
- ✅ **Configuration Management**: Ansible role-based architecture
- ✅ **Cloud Security**: Multi-layer defense, least privilege
- ✅ **Observability**: Real-time monitoring, structured logging
- ✅ **Automation**: Idempotent deployments, zero manual steps
- ✅ **Production-Grade**: Backups, recovery, operational runbooks
- ✅ **Cost-Effective**: ~$15-20/month, optimized resource usage
- ✅ **CDN Integration**: Cloudflare API automation
- ✅ **Documentation**: Architecture diagrams, decision records

## 🤝 Contributing

Contributions welcome! Focus areas:
- RDS integration for managed database
- Auto-scaling group configuration
- CloudWatch alarms and SNS notifications
- S3-backed WordPress media offload
- ECS/Fargate containerized variant

## 📄 License

MIT License - see [LICENSE](LICENSE) file

## ⚠️ Disclaimer

This configuration is production-ready but should be reviewed and customized for your specific security and compliance requirements. Always test in non-production environments first.

## 🔗 References

- [WordPress Security Best Practices](https://wordpress.org/support/article/hardening-wordpress/)
- [Cloudflare WordPress Plugin](https://www.cloudflare.com/integrations/wordpress/)
- [AWS EC2 Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-best-practices.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)

---

**Built with ❤️ for production workloads**
