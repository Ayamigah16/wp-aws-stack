#!/bin/bash
###############################################################################
# Terraform Destroy Script
# Purpose: Safe infrastructure teardown
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

echo "========================================="
echo "WordPress AWS Stack DESTRUCTION"
echo "========================================="
echo ""
echo "⚠️  WARNING: This will PERMANENTLY DELETE:"
echo "  - EC2 instance and all data"
echo "  - Elastic IP"
echo "  - Security Groups"
echo "  - Cloudflare DNS records"
echo ""
read -p "Type 'DESTROY' to confirm: " CONFIRM

if [ "$CONFIRM" != "DESTROY" ]; then
    echo "Destruction cancelled."
    exit 0
fi

cd "$TERRAFORM_DIR"

echo ""
echo "Creating destruction plan..."
terraform plan -destroy -out=destroy.tfplan

echo ""
read -p "Review plan. Proceed with destruction? (yes/no): " FINAL_CONFIRM

if [ "$FINAL_CONFIRM" != "yes" ]; then
    echo "Destruction cancelled."
    rm -f destroy.tfplan
    exit 0
fi

echo ""
echo "Destroying infrastructure..."
terraform apply destroy.tfplan

rm -f destroy.tfplan

echo ""
echo "========================================="
echo "Infrastructure destroyed successfully"
echo "========================================="
