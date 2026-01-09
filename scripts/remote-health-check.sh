#!/bin/bash
###############################################################################
# Remote Health Check Script
# Execute via: ./remote-health-check.sh EC2_IP SSH_KEY
###############################################################################

set -euo pipefail

EC2_IP="${1:-}"
SSH_KEY="${2:-~/.ssh/wordpress-key.pem}"

if [ -z "$EC2_IP" ]; then
    echo "Usage: $0 EC2_IP [SSH_KEY]"
    exit 1
fi

echo "========================================="
echo "Remote Health Check: $EC2_IP"
echo "========================================="
echo ""

ssh -i "$SSH_KEY" ubuntu@"$EC2_IP" 'bash -s' <<'REMOTE_SCRIPT'
#!/bin/bash

echo "=== System Information ==="
echo "Hostname: $(hostname)"
echo "Uptime: $(uptime -p)"
echo "OS: $(lsb_release -ds)"
echo "Kernel: $(uname -r)"
echo ""

echo "=== Service Status ==="
systemctl is-active apache2 && echo "✓ Apache: Running" || echo "✗ Apache: Stopped"
systemctl is-active mysql && echo "✓ MySQL: Running" || echo "✗ MySQL: Stopped"
systemctl is-active fail2ban && echo "✓ Fail2ban: Running" || echo "✗ Fail2ban: Stopped"
systemctl is-active ufw && echo "✓ UFW: Running" || echo "✗ UFW: Stopped"
systemctl is-active netdata && echo "✓ Netdata: Running" || echo "✗ Netdata: Stopped"
echo ""

echo "=== Resource Usage ==="
echo "CPU Load:"
uptime | awk -F'load average:' '{print $2}'
echo ""
echo "Memory Usage:"
free -h | grep Mem
echo ""
echo "Disk Usage:"
df -h / | tail -1
echo ""

echo "=== Network ==="
echo "Listening Ports:"
ss -tlnp | grep -E ':(80|443|22|3306|19999)' || echo "No critical ports found"
echo ""

echo "=== Recent Logs ==="
echo "Apache Errors (last 5):"
tail -5 /var/log/apache2/wordpress_error.log 2>/dev/null || echo "No errors"
echo ""

echo "=== Fail2ban Status ==="
fail2ban-client status | head -10
echo ""

echo "=== WordPress Status ==="
if [ -f /var/www/html/wp-config.php ]; then
    echo "✓ WordPress installed"
    ls -lh /var/www/html/ | head -10
else
    echo "✗ WordPress not found"
fi
echo ""

echo "=== Backup Status ==="
if [ -d /var/backups/wordpress ]; then
    echo "Latest backups:"
    ls -lht /var/backups/wordpress/ | head -5
else
    echo "No backups found"
fi
echo ""

echo "=== Health Check Complete ==="
REMOTE_SCRIPT

echo ""
echo "Health check completed!"
