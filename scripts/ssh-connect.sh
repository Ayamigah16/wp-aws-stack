#!/bin/bash
###############################################################################
# SSH Connection Helper
# Usage: ./ssh-connect.sh
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Try to get IP from Terraform outputs
if [ -f "$PROJECT_ROOT/terraform-outputs.json" ]; then
    EC2_IP=$(cat "$PROJECT_ROOT/terraform-outputs.json" | grep -oP '"instance_public_ip":\s*"\K[^"]+' || echo "")
else
    echo "Terraform outputs not found. Getting from terraform..."
    cd "$PROJECT_ROOT/terraform"
    EC2_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "")
fi

if [ -z "$EC2_IP" ]; then
    echo "ERROR: Could not determine EC2 IP address"
    echo "Run: cd terraform && terraform output instance_public_ip"
    exit 1
fi

echo "Connecting to EC2 instance: $EC2_IP"
echo ""

# Check for SSH key
SSH_KEY=""
if [ -f ~/.ssh/wordpress-key.pem ]; then
    SSH_KEY=~/.ssh/wordpress-key.pem
elif [ -f ~/.ssh/id_rsa ]; then
    SSH_KEY=~/.ssh/id_rsa
else
    read -p "Enter path to SSH private key: " SSH_KEY
fi

if [ ! -f "$SSH_KEY" ]; then
    echo "ERROR: SSH key not found: $SSH_KEY"
    exit 1
fi

# Ensure correct permissions
chmod 600 "$SSH_KEY"

echo "Using SSH key: $SSH_KEY"
echo ""

ssh -i "$SSH_KEY" ubuntu@"$EC2_IP"
