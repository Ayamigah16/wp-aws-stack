terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "wp-terraform-state-wordpress-stack"
    key            = "wp-aws-stack/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock-wp"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "WordPress-AWS-Stack"
      ManagedBy   = "Terraform"
      Environment = var.environment
      Owner       = var.owner_email
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
