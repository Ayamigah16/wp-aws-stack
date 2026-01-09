# WordPress AWS Stack - Modular Terraform Architecture

This Terraform configuration uses a **module-based architecture** for better organization, reusability, and maintainability.

## Module Structure

```
terraform/
├── main.tf              # Root module - orchestrates all modules
├── variables.tf         # Root module variables
├── outputs.tf          # Root module outputs
├── provider.tf         # Provider configurations
├── data.tf             # Shared data sources
├── user-data.sh        # EC2 bootstrap script
├── terraform.tfvars.example
└── modules/
    ├── networking/     # Security Groups, VPC, Cloudflare IP fetching
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── compute/        # EC2, IAM, EIP
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── cloudflare/     # DNS, CDN, WAF, page rules
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## Module Descriptions

### 1. Networking Module (`modules/networking/`)

**Purpose**: Network security and access control

**Resources**:
- Security Groups with Cloudflare IP whitelisting
- VPC and subnet selection
- Ingress/egress rules for HTTP, HTTPS, SSH, Netdata
- Dynamic Cloudflare IP range fetching

**Outputs**:
- `security_group_id`: For EC2 attachment
- `subnet_ids`: For instance placement
- `vpc_id`: VPC identifier
- `cloudflare_ipv4_ranges`: For reference

**Key Features**:
- Fetches latest Cloudflare IP ranges automatically
- Restricts origin access to Cloudflare only
- SSH access limited to specific CIDR
- Optional Netdata access control

### 2. Compute Module (`modules/compute/`)

**Purpose**: EC2 instance and related compute resources

**Resources**:
- EC2 instance with Ubuntu LTS
- IAM role and instance profile
- SSH key pair management
- Elastic IP allocation and association
- EBS volume configuration
- User data bootstrap script integration

**Outputs**:
- `instance_id`: EC2 instance identifier
- `instance_public_ip`: Public IP (EIP or ephemeral)
- `instance_private_ip`: Private VPC IP
- `ami_id`: AMI used for deployment

**Key Features**:
- Automated AMI selection (latest Ubuntu 22.04 LTS)
- IMDSv2 enforcement for security
- EBS encryption at rest
- Detailed monitoring enabled
- IAM roles for SSM and CloudWatch
- Templated user-data with WordPress configuration

### 3. Cloudflare Module (`modules/cloudflare/`)

**Purpose**: CDN, DNS, and edge security configuration

**Resources**:
- DNS A record with proxy enabled
- Zone-level SSL/TLS settings
- WAF managed rulesets
- Rate limiting rules
- Page rules for caching strategies

**Outputs**:
- `dns_record_id`: DNS record identifier
- `dns_record_name`: FQDN
- `dns_record_value`: Origin IP
- `dns_record_proxied`: Proxy status

**Key Features**:
- Automatic DNS configuration
- Full (strict) SSL/TLS mode
- OWASP Top 10 protection via WAF
- Rate limiting on wp-login.php
- Intelligent caching (bypass admin, cache static)
- Minification and compression

## Module Benefits

### 1. **Separation of Concerns**
Each module handles a specific infrastructure layer:
- Networking: Network security
- Compute: Application server
- Cloudflare: Edge services

### 2. **Reusability**
Modules can be:
- Reused across environments (dev, staging, prod)
- Shared across different WordPress deployments
- Published to Terraform Registry

### 3. **Testability**
Each module can be:
- Unit tested independently
- Validated with `terraform validate`
- Documented separately

### 4. **Maintainability**
- Clear boundaries between components
- Easier to update individual modules
- Simplified troubleshooting
- Version control per module

### 5. **Scalability**
Easy to add new modules:
- `monitoring/`: CloudWatch alarms
- `database/`: RDS MySQL
- `storage/`: S3 for media uploads
- `backup/`: Automated backup to S3

## Usage

### Deploy Everything
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Deploy Specific Module (for testing)
```bash
# Only networking changes
terraform plan -target=module.networking
terraform apply -target=module.networking

# Only compute changes
terraform plan -target=module.compute
terraform apply -target=module.compute
```

### Module Dependencies

```
┌─────────────┐
│  networking │
└──────┬──────┘
       │ security_group_id
       │ subnet_ids
       ▼
┌─────────────┐
│   compute   │
└──────┬──────┘
       │ instance_public_ip
       ▼
┌─────────────┐
│ cloudflare  │
└─────────────┘
```

**Dependency Order**:
1. Networking module creates security groups
2. Compute module uses security group ID
3. Cloudflare module uses instance public IP

## Module Versioning (Future)

For production, pin module versions:

```hcl
module "networking" {
  source  = "./modules/networking"
  version = "1.0.0"  # Pin to specific version
  
  # variables...
}
```

Or use remote modules:

```hcl
module "networking" {
  source  = "github.com/your-org/terraform-aws-wordpress//modules/networking?ref=v1.0.0"
  
  # variables...
}
```

## Adding New Modules

### Example: Monitoring Module

```bash
mkdir -p modules/monitoring
touch modules/monitoring/{main.tf,variables.tf,outputs.tf}
```

**modules/monitoring/main.tf**:
```hcl
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  
  dimensions = {
    InstanceId = var.instance_id
  }
  
  alarm_actions = [var.sns_topic_arn]
}
```

**Root main.tf**:
```hcl
module "monitoring" {
  source = "./modules/monitoring"
  
  project_name  = var.project_name
  instance_id   = module.compute.instance_id
  sns_topic_arn = aws_sns_topic.alerts.arn
}
```

## Best Practices

1. **Keep modules focused**: One responsibility per module
2. **Use outputs**: Expose necessary values for other modules
3. **Validate inputs**: Use variable validation blocks
4. **Document modules**: Add README.md to each module
5. **Version modules**: Use semantic versioning
6. **Test modules**: Use Terratest or similar frameworks
7. **Use locals**: For complex logic within modules
8. **Tag everything**: Pass common tags through variables

## Migration from Flat Structure

This refactoring maintains **100% functionality** while improving structure:

✅ All resources preserved  
✅ Same outputs  
✅ Same variables  
✅ Same behavior  
✅ No state migration required (clean deployment)

## Troubleshooting

### Module not found
```bash
# Reinitialize to download modules
terraform init -upgrade
```

### Circular dependencies
Modules are ordered to prevent circular dependencies:
`networking → compute → cloudflare`

### Output not available
Check module outputs in `modules/*/outputs.tf`

## Future Enhancements

Potential additional modules:

- **database**: RDS MySQL with Multi-AZ
- **storage**: S3 bucket for media uploads
- **backup**: Automated backups to S3 with lifecycle
- **monitoring**: CloudWatch alarms and dashboards
- **cdn**: CloudFront as Cloudflare alternative
- **dns**: Route53 for AWS-native DNS
- **waf**: AWS WAF for additional protection

---

**Architecture Type**: Modular  
**Pattern**: Layer-based modules  
**Complexity**: Moderate  
**Maintainability**: High ⭐⭐⭐⭐⭐
