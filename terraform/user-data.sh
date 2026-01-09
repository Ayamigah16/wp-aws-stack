#!/bin/bash
###############################################################################
# WordPress EC2 Bootstrap Script
# Purpose: Automated LAMP stack + WordPress deployment with security hardening
# Execution: Via EC2 user-data (cloud-init)
# Idempotency: Can be re-run safely
###############################################################################

set -euo pipefail

# Enable command logging for debugging
exec > >(tee -a /var/log/wordpress-bootstrap.log)
exec 2>&1

echo "=== WordPress Bootstrap Started: $(date) ==="

# Variables from Terraform templatefile
WP_DB_NAME="${wp_db_name}"
WP_DB_USER="${wp_db_user}"
WP_DB_PASSWORD="${wp_db_password}"
MYSQL_ROOT_PASSWORD="${mysql_root_password}"
DOMAIN_NAME="${domain_name}"
ENABLE_NETDATA="${enable_netdata}"
ENABLE_BACKUPS="${enable_backups}"
BACKUP_RETENTION_DAYS="${backup_retention_days}"

# Constants
WP_DIR="/var/www/html"
SECRETS_FILE="/etc/wordpress-secrets.conf"
BACKUP_DIR="/var/backups/wordpress"

###############################################################################
# Phase 1: System Hardening & Updates
###############################################################################
echo "[1/9] System update and hardening..."

# Update package lists and upgrade system
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y

# Install essential security and management tools
apt-get install -y \
  ufw \
  fail2ban \
  unattended-upgrades \
  apt-listchanges \
  needrestart \
  curl \
  wget \
  git \
  htop \
  vim \
  certbot

# Configure automatic security updates
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "$${distro_id}:$${distro_codename}-security";
    "$${distro_id}ESMApps:$${distro_codename}-apps-security";
    "$${distro_id}ESM:$${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

# Enable automatic updates
echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades

###############################################################################
# Phase 2: Firewall Configuration (UFW)
###############################################################################
echo "[2/9] Configuring firewall..."

# Reset UFW to default
ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH (restricted at Security Group level)
ufw allow 22/tcp comment 'SSH'

# Allow HTTP/HTTPS (Cloudflare only at SG level)
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Allow Netdata if enabled
if [ "$ENABLE_NETDATA" = "true" ]; then
  ufw allow 19999/tcp comment 'Netdata'
fi

# Enable firewall
ufw --force enable

###############################################################################
# Phase 3: LAMP Stack Installation
###############################################################################
echo "[3/9] Installing LAMP stack..."

# Install Apache, PHP, MySQL
apt-get install -y \
  apache2 \
  mysql-server \
  php8.1 \
  php8.1-cli \
  php8.1-mysql \
  php8.1-curl \
  php8.1-gd \
  php8.1-mbstring \
  php8.1-xml \
  php8.1-xmlrpc \
  php8.1-soap \
  php8.1-intl \
  php8.1-zip \
  php8.1-bcmath \
  php8.1-imagick \
  libapache2-mod-php8.1

# Enable required Apache modules
a2enmod rewrite
a2enmod ssl
a2enmod headers
a2enmod expires
a2enmod remoteip

# Configure Apache to trust Cloudflare IPs
cat > /etc/apache2/conf-available/cloudflare.conf <<'EOF'
# Trust Cloudflare proxy IPs
RemoteIPHeader CF-Connecting-IP
RemoteIPTrustedProxy 173.245.48.0/20
RemoteIPTrustedProxy 103.21.244.0/22
RemoteIPTrustedProxy 103.22.200.0/22
RemoteIPTrustedProxy 103.31.4.0/22
RemoteIPTrustedProxy 141.101.64.0/18
RemoteIPTrustedProxy 108.162.192.0/18
RemoteIPTrustedProxy 190.93.240.0/20
RemoteIPTrustedProxy 188.114.96.0/20
RemoteIPTrustedProxy 197.234.240.0/22
RemoteIPTrustedProxy 198.41.128.0/17
RemoteIPTrustedProxy 162.158.0.0/15
RemoteIPTrustedProxy 104.16.0.0/13
RemoteIPTrustedProxy 104.24.0.0/14
RemoteIPTrustedProxy 172.64.0.0/13
RemoteIPTrustedProxy 131.0.72.0/22
EOF

a2enconf cloudflare

# PHP security hardening
cat > /etc/php/8.1/apache2/conf.d/99-wordpress-security.ini <<'EOF'
; Security hardening
expose_php = Off
display_errors = Off
log_errors = On
error_log = /var/log/php_errors.log
max_execution_time = 60
max_input_time = 60
memory_limit = 256M
post_max_size = 64M
upload_max_filesize = 64M
allow_url_fopen = On
allow_url_include = Off

; Session security
session.cookie_httponly = 1
session.cookie_secure = 1
session.use_strict_mode = 1
EOF

systemctl restart apache2

###############################################################################
# Phase 4: MySQL Security & Database Setup
###############################################################################
echo "[4/9] Securing MySQL and creating database..."

# Set root password and secure installation
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<MYSQL_SECURE
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
MYSQL_SECURE

# Create WordPress database and user
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<MYSQL_WP
CREATE DATABASE IF NOT EXISTS $WP_DB_NAME DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$WP_DB_USER'@'localhost' IDENTIFIED BY '$WP_DB_PASSWORD';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER, CREATE TEMPORARY TABLES, LOCK TABLES ON $WP_DB_NAME.* TO '$WP_DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_WP

# MySQL performance tuning (basic)
cat >> /etc/mysql/mysql.conf.d/mysqld.cnf <<'EOF'

# Performance tuning for WordPress
max_connections = 50
innodb_buffer_pool_size = 256M
innodb_log_file_size = 64M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
query_cache_size = 0
query_cache_type = 0
EOF

systemctl restart mysql

###############################################################################
# Phase 5: WordPress Installation
###############################################################################
echo "[5/9] Installing WordPress..."

# Download latest WordPress
cd /tmp
wget -q https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz

# Move WordPress files
rm -rf $WP_DIR/*
cp -r wordpress/* $WP_DIR/
rm -rf wordpress latest.tar.gz

# Generate WordPress salts
SALTS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)

# Create wp-config.php
cat > $WP_DIR/wp-config.php <<WPCONFIG
<?php
/**
 * WordPress Configuration
 * Generated by automated deployment
 */

// ** Database settings ** //
define( 'DB_NAME', '$WP_DB_NAME' );
define( 'DB_USER', '$WP_DB_USER' );
define( 'DB_PASSWORD', '$WP_DB_PASSWORD' );
define( 'DB_HOST', 'localhost' );
define( 'DB_CHARSET', 'utf8mb4' );
define( 'DB_COLLATE', '' );

// ** Authentication Unique Keys and Salts ** //
$SALTS

// ** WordPress Table prefix ** //
\$table_prefix = 'wp_';

// ** Cloudflare SSL/HTTPS Handling ** //
if (isset(\$_SERVER['HTTP_CF_VISITOR'])) {
    \$cf_visitor = json_decode(\$_SERVER['HTTP_CF_VISITOR']);
    if (\$cf_visitor->scheme == 'https') {
        \$_SERVER['HTTPS'] = 'on';
    }
}

// Trust Cloudflare proxied HTTPS
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    \$_SERVER['HTTPS'] = 'on';
}

// Force SSL for admin and login
define( 'FORCE_SSL_ADMIN', true );

// Security hardening
define( 'DISALLOW_FILE_EDIT', true );
define( 'DISALLOW_FILE_MODS', false );
define( 'WP_AUTO_UPDATE_CORE', 'minor' );

// Debugging (disable in production after initial setup)
define( 'WP_DEBUG', false );
define( 'WP_DEBUG_LOG', true );
define( 'WP_DEBUG_DISPLAY', false );
@ini_set( 'display_errors', 0 );

// Memory and performance
define( 'WP_MEMORY_LIMIT', '256M' );
define( 'WP_MAX_MEMORY_LIMIT', '512M' );

// Absolute path to WordPress directory
if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

// Sets up WordPress vars and included files
require_once ABSPATH . 'wp-settings.php';
WPCONFIG

# Set proper permissions
chown -R www-data:www-data $WP_DIR
find $WP_DIR -type d -exec chmod 755 {} \;
find $WP_DIR -type f -exec chmod 644 {} \;

# Secure wp-config.php
chmod 640 $WP_DIR/wp-config.php

# Create uploads directory with proper permissions
mkdir -p $WP_DIR/wp-content/uploads
chown -R www-data:www-data $WP_DIR/wp-content/uploads
chmod 755 $WP_DIR/wp-content/uploads

###############################################################################
# Phase 6: Apache Virtual Host Configuration
###############################################################################
echo "[6/9] Configuring Apache virtual host..."

cat > /etc/apache2/sites-available/wordpress.conf <<VHOST
<VirtualHost *:80>
    ServerName $DOMAIN_NAME
    ServerAlias www.$DOMAIN_NAME
    ServerAdmin admin@$DOMAIN_NAME
    
    DocumentRoot $WP_DIR
    
    <Directory $WP_DIR>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    # Security headers
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
    
    # Hide server signature
    ServerSignature Off
    
    # Logging
    ErrorLog \${APACHE_LOG_DIR}/wordpress_error.log
    CustomLog \${APACHE_LOG_DIR}/wordpress_access.log combined
    
    # PHP performance
    <IfModule mod_php8.c>
        php_value upload_max_filesize 64M
        php_value post_max_size 64M
        php_value memory_limit 256M
        php_value max_execution_time 60
        php_value max_input_time 60
    </IfModule>
</VirtualHost>
VHOST

# Disable default site and enable WordPress
a2dissite 000-default.conf
a2ensite wordpress.conf

# Test Apache configuration
apache2ctl configtest

# Restart Apache
systemctl restart apache2

###############################################################################
# Phase 7: Security Hardening - Fail2ban
###############################################################################
echo "[7/9] Configuring fail2ban..."

# Apache auth jail
cat > /etc/fail2ban/jail.d/apache.conf <<'EOF'
[apache-auth]
enabled = true
port = http,https
logpath = %(apache_error_log)s
maxretry = 3
bantime = 3600

[apache-badbots]
enabled = true
port = http,https
logpath = %(apache_access_log)s
maxretry = 2
bantime = 86400

[apache-noscript]
enabled = true
port = http,https
logpath = %(apache_error_log)s
maxretry = 3

[apache-overflows]
enabled = true
port = http,https
logpath = %(apache_error_log)s
maxretry = 2
EOF

# WordPress specific protection
cat > /etc/fail2ban/filter.d/wordpress.conf <<'EOF'
[Definition]
failregex = ^<HOST> .* "POST .*wp-login.php
            ^<HOST> .* "POST .*xmlrpc.php
ignoreregex =
EOF

cat > /etc/fail2ban/jail.d/wordpress.conf <<'EOF'
[wordpress]
enabled = true
filter = wordpress
logpath = /var/log/apache2/wordpress_access.log
port = http,https
maxretry = 3
bantime = 3600
findtime = 600
EOF

systemctl enable fail2ban
systemctl restart fail2ban

###############################################################################
# Phase 8: Monitoring - Netdata
###############################################################################
if [ "$ENABLE_NETDATA" = "true" ]; then
  echo "[8/9] Installing Netdata monitoring..."
  
  # Install Netdata (automatic install script)
  wget -O /tmp/netdata-kickstart.sh https://my-netdata.io/kickstart.sh
  sh /tmp/netdata-kickstart.sh --non-interactive --stable-channel --dont-wait
  
  # Configure Netdata
  cat > /etc/netdata/netdata.conf <<'EOF'
[global]
    update every = 5
    memory mode = dbengine
    
[web]
    bind to = 0.0.0.0:19999
    allow connections from = *
    
[plugins]
    # Enable Apache monitoring
    apache = yes
    mysql = yes
EOF
  
  # Enable Apache status for Netdata
  a2enmod status
  cat > /etc/apache2/conf-available/netdata-status.conf <<'EOF'
<Location "/server-status">
    SetHandler server-status
    Require local
    Require ip 127.0.0.1
</Location>
EOF
  a2enconf netdata-status
  systemctl reload apache2
  
  # Configure MySQL monitoring for Netdata
  mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<MYSQL_NETDATA
CREATE USER IF NOT EXISTS 'netdata'@'localhost';
GRANT USAGE, REPLICATION CLIENT, PROCESS ON *.* TO 'netdata'@'localhost';
FLUSH PRIVILEGES;
MYSQL_NETDATA
  
  systemctl restart netdata
else
  echo "[8/9] Netdata monitoring disabled"
fi

###############################################################################
# Phase 9: Backup Automation
###############################################################################
if [ "$ENABLE_BACKUPS" = "true" ]; then
  echo "[9/9] Configuring automated backups..."
  
  # Create backup directory
  mkdir -p $BACKUP_DIR
  chmod 700 $BACKUP_DIR
  
  # Create backup script
  cat > /usr/local/bin/wordpress-backup.sh <<'BACKUP_SCRIPT'
#!/bin/bash
###############################################################################
# WordPress Backup Script
# Backs up database and WordPress files
###############################################################################

set -euo pipefail

BACKUP_DIR="/var/backups/wordpress"
WP_DIR="/var/www/html"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS="${backup_retention_days}"

# Source database credentials
source /etc/wordpress-secrets.conf

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup database
mysqldump -u "$WP_DB_USER" -p"$WP_DB_PASSWORD" "$WP_DB_NAME" | gzip > "$BACKUP_DIR/db_$TIMESTAMP.sql.gz"

# Backup WordPress files
tar -czf "$BACKUP_DIR/files_$TIMESTAMP.tar.gz" -C "$(dirname $WP_DIR)" "$(basename $WP_DIR)"

# Remove old backups
find "$BACKUP_DIR" -name "db_*.sql.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "files_*.tar.gz" -mtime +$RETENTION_DAYS -delete

# Log completion
echo "$(date): Backup completed - $TIMESTAMP" >> /var/log/wordpress-backup.log

# Optional: Upload to S3 (uncomment and configure)
# aws s3 cp "$BACKUP_DIR/db_$TIMESTAMP.sql.gz" "s3://your-backup-bucket/wordpress/db/"
# aws s3 cp "$BACKUP_DIR/files_$TIMESTAMP.tar.gz" "s3://your-backup-bucket/wordpress/files/"
BACKUP_SCRIPT
  
  chmod +x /usr/local/bin/wordpress-backup.sh
  
  # Create cron job (daily at 2 AM)
  cat > /etc/cron.d/wordpress-backup <<'CRON'
0 2 * * * root /usr/local/bin/wordpress-backup.sh >> /var/log/wordpress-backup.log 2>&1
CRON
  
  chmod 644 /etc/cron.d/wordpress-backup
else
  echo "[9/9] Automated backups disabled"
fi

###############################################################################
# Store Credentials Securely
###############################################################################
cat > $SECRETS_FILE <<SECRETS
# WordPress Database Credentials
# Permissions: 600 (root only)
WP_DB_NAME="$WP_DB_NAME"
WP_DB_USER="$WP_DB_USER"
WP_DB_PASSWORD="$WP_DB_PASSWORD"
MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD"
SECRETS

chmod 600 $SECRETS_FILE

###############################################################################
# Final System Configuration
###############################################################################

# Disable unnecessary services
systemctl disable bluetooth.service 2>/dev/null || true
systemctl disable cups.service 2>/dev/null || true

# Set timezone to UTC
timedatectl set-timezone UTC

# Enable services
systemctl enable apache2
systemctl enable mysql
systemctl enable ufw
systemctl enable fail2ban

# Create status indicator
cat > /root/deployment-complete.txt <<STATUS
WordPress Deployment Completed: $(date)
Domain: $DOMAIN_NAME
Database: $WP_DB_NAME
WordPress Directory: $WP_DIR
Netdata Enabled: $ENABLE_NETDATA
Backups Enabled: $ENABLE_BACKUPS

Next Steps:
1. Visit https://$DOMAIN_NAME to complete WordPress installation
2. Run validation script: /usr/local/bin/validate-deployment.sh
3. Check logs: /var/log/wordpress-bootstrap.log

Security Notes:
- Database credentials: $SECRETS_FILE
- Fail2ban active
- UFW firewall enabled
- Automatic security updates enabled
STATUS

echo "=== WordPress Bootstrap Completed: $(date) ==="
echo "System will be ready in 1-2 minutes. Check /root/deployment-complete.txt"
