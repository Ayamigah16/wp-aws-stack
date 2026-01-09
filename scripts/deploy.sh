#!/bin/bash
###############################################################################
# Terraform Deployment Script
# Purpose: Streamlined deployment with validation
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

echo "========================================="
echo "WordPress AWS Stack Deployment"
echo "========================================="
echo ""

# Check prerequisites
command -v terraform >/dev/null 2>&1 || { echo "ERROR: terraform not found"; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "ERROR: aws-cli not found"; exit 1; }

# Navigate to Terraform directory
cd "$TERRAFORM_DIR"

# Check for terraform.tfvars
if [ ! -f "terraform.tfvars" ]; then
    echo "ERROR: terraform.tfvars not found!"
    echo "Copy terraform.tfvars.example and configure your values:"
    echo "  cp terraform.tfvars.example terraform.tfvars"
    echo "  vim terraform.tfvars"
    exit 1
fi

# Initialize Terraform
echo "[1/5] Initializing Terraform..."
terraform init

# Validate configuration
echo "[2/5] Validating Terraform configuration..."
terraform validate

# Format check
echo "[3/5] Checking Terraform formatting..."
terraform fmt -check || {
    echo "Formatting issues detected. Auto-formatting..."
    terraform fmt -recursive
}

# Plan
echo "[4/5] Creating execution plan..."
terraform plan -out=tfplan

echo ""
read -p "Review plan above. Apply changes? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled."
    rm -f tfplan
    exit 0
fi

# Apply
echo "[5/5] Applying infrastructure changes..."
terraform apply tfplan

rm -f tfplan

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
terraform output -json > "$PROJECT_ROOT/terraform-outputs.json"
terraform output

echo ""
echo "Next Steps:"
echo "1. Wait 5-10 minutes for EC2 bootstrap to complete"
echo "2. Run validation: cd ../scripts && ./validate.sh \$(terraform output -raw instance_public_ip) \$(terraform output -raw domain_name)"
echo "3. Visit: https://\$(terraform output -raw domain_name)"
echo "4. Complete WordPress installation via web UI"
