#!/bin/bash
# Script to setup S3 backend for Terraform state management
# This automates the chicken-and-egg problem of creating backend resources

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

echo "=========================================="
echo "Terraform S3 Backend Setup"
echo "=========================================="
echo ""

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Error: terraform is not installed"
    exit 1
fi

cd "$TERRAFORM_DIR"

# Check if provider.tf has backend configured
if grep -q "^[[:space:]]*backend \"s3\"" provider.tf; then
    echo "⚠️  Backend configuration found in provider.tf"
    echo ""
    echo "Step 1: Comment out backend block..."
    
    # Backup provider.tf
    cp provider.tf provider.tf.backup
    echo "✅ Created backup: provider.tf.backup"
    
    # Comment out backend block
    sed -i '/backend "s3" {/,/^[[:space:]]*}[[:space:]]*$/s/^/# /' provider.tf
    echo "✅ Temporarily commented out backend configuration"
    echo ""
fi

echo "Step 2: Creating S3 bucket and DynamoDB table..."
echo ""

# Initialize Terraform (local backend)
terraform init -reconfigure

# Show plan
echo ""
echo "Preview of resources to be created:"
terraform plan -target=aws_s3_bucket.terraform_state \
               -target=aws_s3_bucket_versioning.terraform_state \
               -target=aws_s3_bucket_server_side_encryption_configuration.terraform_state \
               -target=aws_s3_bucket_public_access_block.terraform_state \
               -target=aws_dynamodb_table.terraform_state_lock

echo ""
read -p "Create these resources? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Cancelled by user"
    
    # Restore provider.tf if backup exists
    if [ -f provider.tf.backup ]; then
        mv provider.tf.backup provider.tf
        echo "✅ Restored provider.tf from backup"
    fi
    exit 1
fi

# Apply only backend resources
terraform apply -auto-approve \
    -target=aws_s3_bucket.terraform_state \
    -target=aws_s3_bucket_versioning.terraform_state \
    -target=aws_s3_bucket_server_side_encryption_configuration.terraform_state \
    -target=aws_s3_bucket_public_access_block.terraform_state \
    -target=aws_dynamodb_table.terraform_state_lock

echo ""
echo "✅ Backend resources created successfully!"
echo ""

# Restore provider.tf with backend configuration
if [ -f provider.tf.backup ]; then
    mv provider.tf.backup provider.tf
    echo "✅ Restored backend configuration in provider.tf"
    echo ""
fi

echo "Step 3: Migrating state to S3 backend..."
echo ""

# Initialize with backend migration
terraform init -migrate-state -force-copy

echo ""
echo "=========================================="
echo "✅ S3 Backend Setup Complete!"
echo "=========================================="
echo ""
echo "State is now stored in S3 with DynamoDB locking."
echo ""
echo "Next steps:"
echo "1. Verify state bucket: aws s3 ls | grep terraform-state"
echo "2. Verify DynamoDB table: aws dynamodb list-tables | grep terraform-state-lock"
echo "3. (Optional) Delete or comment out backend-resources.tf"
echo ""
echo "Important: backend-resources.tf can now be removed from the"
echo "configuration as the S3 bucket and DynamoDB table are created."
echo "The backend configuration in provider.tf will manage them going forward."
echo ""
