# Operations Manual

## Operational Procedures

### Daily Operations

#### System Health Check

```bash
# Automated check
./scripts/remote-health-check.sh <EC2_IP>

# Manual verification
ssh ubuntu@<EC2_IP>
sudo systemctl status apache2 mysql fail2ban netdata
```

**Expected Output**:
- All services: `active (running)`
- CPU load: < 1.0
- Memory usage: < 80%
- Disk usage: < 85%

#### Log Monitoring

```bash
# Apache access (look for unusual patterns)
sudo tail -100 /var/log/apache2/wordpress_access.log | grep -v "200\|304"

# Apache errors
sudo tail -50 /var/log/apache2/wordpress_error.log

# Fail2ban activity
sudo fail2ban-client status wordpress

# MySQL slow queries
sudo grep "Query_time" /var/log/mysql/slow-query.log
```

### Deployment Procedures

#### Initial Deployment

**Prerequisites**:
1. AWS credentials configured (`~/.aws/credentials`)
2. Cloudflare account with domain
3. SSH key pair generated

**Steps**:
```bash
# 1. Clone repository
git clone <repo-url>
cd wp-aws-stack

# 2. Configure Terraform
cd terraform
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Fill in required values

# 3. Deploy infrastructure
cd ../scripts
chmod +x *.sh
./deploy.sh

# 4. Wait for bootstrap (5-10 minutes)
# Monitor: sudo tail -f /var/log/cloud-init-output.log

# 5. Validate deployment
./validate.sh <EC2_IP> <DOMAIN_NAME>

# 6. Complete WordPress setup
# Visit https://your-domain.com
```

**Deployment Time**: ~15 minutes total

#### Rolling Updates

**WordPress Core Update**:
```bash
ssh ubuntu@<EC2_IP>

# Backup first
sudo /usr/local/bin/wordpress-backup.sh

# Update
sudo -u www-data wp core update
sudo -u www-data wp core update-db

# Verify
sudo -u www-data wp core version
```

**Plugin Update**:
```bash
# List outdated plugins
sudo -u www-data wp plugin list --update=available

# Update specific plugin
sudo -u www-data wp plugin update <plugin-name>

# Update all (caution: test in staging first)
sudo -u www-data wp plugin update --all
```

**PHP Version Update** (e.g., 8.1 → 8.2):
```bash
# Add PHP repository
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update

# Install new PHP version
sudo apt install php8.2 php8.2-{cli,mysql,curl,gd,mbstring,xml,xmlrpc,soap,intl,zip,bcmath,imagick} libapache2-mod-php8.2

# Disable old version
sudo a2dismod php8.1
sudo a2enmod php8.2

# Copy configuration
sudo cp /etc/php/8.1/apache2/conf.d/99-wordpress-security.ini /etc/php/8.2/apache2/conf.d/

# Restart Apache
sudo systemctl restart apache2

# Verify
php -v
```

#### Infrastructure Changes

**Resize Instance**:
```bash
cd terraform
vim terraform.tfvars  # Change instance_type

terraform plan  # Verify changes
terraform apply

# Note: Instance will be stopped and started (5 min downtime)
```

**Add Security Group Rule**:
```bash
cd terraform
vim main.tf  # Add new aws_vpc_security_group_ingress_rule

terraform plan
terraform apply
```

### Backup and Recovery

#### Manual Backup

```bash
ssh ubuntu@<EC2_IP>
sudo /usr/local/bin/wordpress-backup.sh
```

**Backup Verification**:
```bash
ls -lh /var/backups/wordpress/
# Should see: db_YYYYMMDD_HHMMSS.sql.gz and files_YYYYMMDD_HHMMSS.tar.gz
```

#### Restore from Backup

**Scenario**: Database corruption or bad plugin install

```bash
ssh ubuntu@<EC2_IP>

# 1. List available backups
ls -lht /var/backups/wordpress/ | head -10

# 2. Choose backup (format: YYYYMMDD_HHMMSS)
TIMESTAMP="20260109_020000"

# 3. Restore (will prompt for confirmation)
sudo /usr/local/bin/wordpress-restore.sh $TIMESTAMP

# 4. Verify site
curl -I https://your-domain.com

# 5. Clear Cloudflare cache
# Visit Cloudflare dashboard → Caching → Purge Everything
```

**Restore Time**: ~5 minutes

#### Disaster Recovery: Complete Instance Loss

```bash
# 1. Verify backups exist (if stored on EBS, they're lost!)
# This is why S3 backup upload is recommended

# 2. Redeploy infrastructure
cd terraform
terraform apply  # Will recreate instance with same EIP

# 3. Wait for bootstrap

# 4. If backups on S3, restore:
ssh ubuntu@<NEW_EC2_IP>
aws s3 cp s3://your-bucket/backups/db_latest.sql.gz /tmp/
aws s3 cp s3://your-bucket/backups/files_latest.tar.gz /tmp/

# Manual restore (adapt restore script)
gunzip < /tmp/db_latest.sql.gz | mysql -u root -p wordpress
tar -xzf /tmp/files_latest.tar.gz -C /var/www/
```

**RTO**: 30-40 minutes

### Monitoring and Alerting

#### Accessing Netdata

**If publicly accessible** (netdata_allowed_cidr configured):
```
http://<EC2_IP>:19999
```

**Via SSH tunnel** (more secure):
```bash
ssh -L 19999:localhost:19999 ubuntu@<EC2_IP>
# Then visit: http://localhost:19999
```

**Key Metrics to Monitor**:
- System → CPU (keep < 70%)
- System → RAM (keep < 80%)
- Disk → Utilization (keep < 85%)
- Apache → Requests/s (baseline for anomaly detection)
- MySQL → Queries/s, Connections

#### Setting Up CloudWatch Alarms

**Create SNS Topic**:
```bash
aws sns create-topic --name wordpress-alerts
aws sns subscribe --topic-arn arn:aws:sns:region:account:wordpress-alerts \
  --protocol email --notification-endpoint your-email@example.com
```

**Create Alarms**:
```bash
# CPU Alarm
aws cloudwatch put-metric-alarm \
  --alarm-name wordpress-high-cpu \
  --alarm-description "CPU usage > 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=InstanceId,Value=<INSTANCE_ID> \
  --alarm-actions arn:aws:sns:region:account:wordpress-alerts

# Disk Alarm
aws cloudwatch put-metric-alarm \
  --alarm-name wordpress-disk-full \
  --metric-name DiskSpaceUtilization \
  --namespace System/Linux \
  --statistic Average \
  --period 300 \
  --threshold 85 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --dimensions Name=InstanceId,Value=<INSTANCE_ID> \
  --alarm-actions arn:aws:sns:region:account:wordpress-alerts
```

### Performance Tuning

#### Identify Performance Bottlenecks

```bash
# 1. Check Apache server-status
curl http://localhost/server-status

# 2. MySQL slow query log
sudo mysql -u root -p -e "SHOW VARIABLES LIKE 'slow_query_log%';"
sudo tail -50 /var/log/mysql/slow-query.log

# 3. PHP-FPM status (if using FPM)
curl http://localhost/fpm-status

# 4. System load
uptime
top -bn1 | head -20
```

#### Apache Tuning

**Enable HTTP/2**:
```bash
sudo a2enmod http2
sudo systemctl restart apache2
```

**MPM Configuration** (`/etc/apache2/mods-available/mpm_prefork.conf`):
```apache
<IfModule mpm_prefork_module>
    StartServers             5
    MinSpareServers          5
    MaxSpareServers         10
    MaxRequestWorkers       150  # Increase for high traffic
    MaxConnectionsPerChild  3000
</IfModule>
```

#### MySQL Tuning

**Optimize for WordPress** (`/etc/mysql/mysql.conf.d/mysqld.cnf`):
```ini
[mysqld]
# Buffer pool (50-70% of available RAM)
innodb_buffer_pool_size = 1G  # For 2GB RAM instance

# Performance
innodb_flush_log_at_trx_commit = 2  # Faster, slight data loss risk
innodb_flush_method = O_DIRECT       # Bypass OS cache
query_cache_size = 0                 # Disabled (deprecated in MySQL 8)
query_cache_type = 0

# Connections
max_connections = 100                # Increase if hitting limit
```

**Apply changes**:
```bash
sudo systemctl restart mysql
```

**Warning**: Test in staging first. Incorrect settings can prevent MySQL startup.

#### PHP Tuning

**OPcache Configuration** (`/etc/php/8.1/apache2/conf.d/10-opcache.ini`):
```ini
opcache.enable=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.revalidate_freq=60
opcache.fast_shutdown=1
```

**Restart Apache**:
```bash
sudo systemctl restart apache2
```

#### Cloudflare Optimization

**Page Rules** (Free tier: 3 rules):
1. **Cache Everything** (static assets): `*example.com/*.{jpg,css,js}`
2. **Bypass Cache** (admin): `*example.com/wp-admin*`
3. **Bypass Cache** (login): `*example.com/wp-login.php*`

**Advanced Settings**:
- Auto Minify: Enable CSS, JS, HTML
- Brotli: Enable
- HTTP/2: Enable
- TLS 1.3: Enable

### Security Operations

#### Review Security Logs

**Daily**:
```bash
# Failed login attempts
sudo journalctl -u ssh | grep "Failed password" | tail -20

# Fail2ban bans
sudo fail2ban-client status wordpress

# Large POST requests (potential attacks)
sudo grep "POST" /var/log/apache2/wordpress_access.log | awk '$10 > 1000000'
```

**Weekly**:
```bash
# Check for malware in WordPress files
sudo grep -r "eval(base64_decode" /var/www/html/ || echo "Clean"
sudo grep -r "gzinflate" /var/www/html/ || echo "Clean"

# Check for unauthorized users
sudo -u www-data wp user list --role=administrator
```

#### Security Incident Response

**Suspected Compromise**:
```bash
# 1. Create snapshot immediately
aws ec2 create-snapshot --volume-id <VOL_ID> --description "Incident-$(date +%Y%m%d)"

# 2. Isolate instance (change security group)
aws ec2 modify-instance-attribute --instance-id <ID> --groups sg-emergency

# 3. Collect forensic data
ssh ubuntu@<EC2_IP>
sudo tar -czf /tmp/forensics-$(date +%Y%m%d).tar.gz /var/log /var/www/html

# 4. Analyze
# Check file modification times
find /var/www/html -type f -mtime -1  # Files modified in last 24h

# Check running processes
ps aux | grep -E "php|apache"

# Check crontabs
sudo crontab -l
sudo cat /etc/cron.d/*

# 5. If compromised, wipe and restore
sudo /usr/local/bin/wordpress-restore.sh <KNOWN_GOOD_BACKUP>
```

#### Rotate Credentials

**Database Credentials**:
```bash
# Generate new password
NEW_DB_PASS=$(openssl rand -base64 24)

# Update MySQL
mysql -u root -p -e "ALTER USER 'wpuser'@'localhost' IDENTIFIED BY '$NEW_DB_PASS';"

# Update wp-config.php
sudo sed -i "s/define( 'DB_PASSWORD', '.*' );/define( 'DB_PASSWORD', '$NEW_DB_PASS' );/" /var/www/html/wp-config.php

# Update secrets file
sudo sed -i "s/WP_DB_PASSWORD=.*/WP_DB_PASSWORD=\"$NEW_DB_PASS\"/" /etc/wordpress-secrets.conf

# Restart Apache
sudo systemctl restart apache2
```

**SSH Keys**:
```bash
# Generate new key locally
ssh-keygen -t rsa -b 4096 -f ~/.ssh/wordpress-new

# Add to authorized_keys on server
ssh ubuntu@<EC2_IP>
echo "<NEW_PUBLIC_KEY>" >> ~/.ssh/authorized_keys

# Test new key
ssh -i ~/.ssh/wordpress-new ubuntu@<EC2_IP>

# Remove old key
vim ~/.ssh/authorized_keys  # Delete old key line
```

### Troubleshooting

#### WordPress White Screen of Death

**Symptoms**: Blank page, no errors displayed

**Diagnosis**:
```bash
# Enable debugging
sudo vim /var/www/html/wp-config.php
# Set: define('WP_DEBUG', true);

# Check error log
sudo tail -100 /var/www/html/wp-content/debug.log
```

**Common Causes**:
1. PHP memory limit exceeded → Increase in `php.ini`
2. Plugin conflict → Disable via: `sudo -u www-data wp plugin deactivate --all`
3. Theme error → Switch to default: `sudo -u www-data wp theme activate twentytwentythree`

#### 502 Bad Gateway

**Symptoms**: Cloudflare shows 502 error

**Diagnosis**:
```bash
# Check Apache status
sudo systemctl status apache2

# Check Apache error log
sudo tail -50 /var/log/apache2/wordpress_error.log

# Check if Apache is listening
sudo netstat -tlnp | grep :80
```

**Fixes**:
```bash
# Restart Apache
sudo systemctl restart apache2

# If MySQL is down
sudo systemctl restart mysql

# Check disk space (full disk causes 502)
df -h
```

#### High CPU Usage

**Diagnosis**:
```bash
# Identify top processes
top -bn1 | head -20

# Check Apache processes
ps aux | grep apache2 | wc -l

# Check MySQL queries
sudo mysql -u root -p -e "SHOW PROCESSLIST;"
```

**Fixes**:
```bash
# If Apache workers maxed out, increase MaxRequestWorkers
sudo vim /etc/apache2/mods-available/mpm_prefork.conf

# If MySQL query causing load, kill it
sudo mysql -u root -p -e "KILL <PROCESS_ID>;"

# Temporary: Restart services
sudo systemctl restart apache2 mysql
```

#### Disk Full

**Symptoms**: Site slow/unavailable, writes failing

**Diagnosis**:
```bash
df -h
du -sh /var/* | sort -h
```

**Cleanup**:
```bash
# Clean old logs
sudo journalctl --vacuum-time=7d
sudo find /var/log -name "*.gz" -mtime +30 -delete

# Clean old backups
sudo find /var/backups/wordpress -name "*.tar.gz" -mtime +14 -delete

# Clean apt cache
sudo apt-get clean

# If still full, expand EBS volume
# See: Resize EBS Volume section
```

#### Cloudflare Caching Issues

**Problem**: Updates not visible on site

**Diagnosis**:
```bash
curl -I https://your-domain.com | grep -i "cf-cache"
```

**Fix**:
1. Cloudflare Dashboard → Caching → Purge Everything
2. Or use API:
   ```bash
   curl -X POST "https://api.cloudflare.com/client/v4/zones/<ZONE_ID>/purge_cache" \
     -H "Authorization: Bearer <TOKEN>" \
     -H "Content-Type: application/json" \
     --data '{"purge_everything":true}'
   ```

### Maintenance Windows

#### Scheduled Maintenance

**Recommended Schedule**:
- **Security patches**: Automatic (daily, unattended-upgrades)
- **WordPress updates**: Monthly (manual, off-peak hours)
- **PHP/MySQL updates**: Quarterly (manual, maintenance window)

**Procedure**:
```bash
# 1. Notify users (if high-traffic site)
# 2. Create pre-maintenance backup
sudo /usr/local/bin/wordpress-backup.sh

# 3. Enable maintenance mode
sudo -u www-data wp maintenance-mode activate

# 4. Perform updates
sudo -u www-data wp core update
sudo -u www-data wp plugin update --all
sudo -u www-data wp theme update --all

# 5. Test
curl -I https://your-domain.com

# 6. Disable maintenance mode
sudo -u www-data wp maintenance-mode deactivate

# 7. Monitor for 1 hour post-update
watch -n 60 'curl -s -o /dev/null -w "%{http_code}" https://your-domain.com'
```

#### Emergency Maintenance

**Unplanned Outage**:
```bash
# 1. Check status
./scripts/remote-health-check.sh <EC2_IP>

# 2. If instance unreachable, check AWS console
aws ec2 describe-instance-status --instance-ids <ID>

# 3. If status checks failing, reboot
aws ec2 reboot-instances --instance-ids <ID>

# 4. If persistent, restore from backup or redeploy
cd terraform
terraform destroy -target=aws_instance.wordpress
terraform apply
```

### Capacity Planning

#### When to Scale Up

**Metrics Indicating Scale Need**:
- Sustained CPU > 70%
- Memory usage > 80%
- Apache MaxRequestWorkers reached
- Slow page load times (> 3s)

**Vertical Scaling**:
```
t3.small (2 vCPU, 2GB) → t3.medium (2 vCPU, 4GB)    [Memory-bound]
t3.small → t3.large (2 vCPU, 8GB)                    [CPU-bound]
```

**Horizontal Scaling** (requires architecture change):
- Deploy ALB + Auto Scaling Group
- Migrate to RDS for shared database
- Use EFS or S3 for shared media storage

### Decommissioning

**Graceful Shutdown**:
```bash
# 1. Final backup
ssh ubuntu@<EC2_IP>
sudo /usr/local/bin/wordpress-backup.sh

# 2. Download backups
scp -r ubuntu@<EC2_IP>:/var/backups/wordpress ~/local-backups/

# 3. Export WordPress content
sudo -u www-data wp export --dir=/tmp/wp-export

# 4. Destroy infrastructure
cd terraform
./scripts/destroy.sh  # Confirms deletion

# 5. Delete Cloudflare DNS record (if needed)
# Manual via dashboard or Terraform destroy
```

---

**Document Version**: 1.0  
**Last Updated**: January 2026  
**Maintained By**: DevOps Team
