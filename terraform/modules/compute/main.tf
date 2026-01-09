# Fetch latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = [var.ami_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# SSH Key Pair
resource "aws_key_pair" "wordpress" {
  key_name_prefix = "${var.project_name}-"
  public_key      = var.ssh_public_key

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-keypair"
    }
  )
}

# IAM Role for EC2 (for CloudWatch, SSM, future enhancements)
resource "aws_iam_role" "wordpress_ec2" {
  name_prefix = "${var.project_name}-ec2-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-ec2-role"
    }
  )
}

# Attach SSM managed policy (allows Session Manager access, reducing SSH dependency)
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.wordpress_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent policy (for future metrics/logs integration)
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.wordpress_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "wordpress" {
  name_prefix = "${var.project_name}-"
  role        = aws_iam_role.wordpress_ec2.name

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-instance-profile"
    }
  )
}

# Elastic IP (optional but recommended for static IP management)
resource "aws_eip" "wordpress" {
  count  = var.enable_eip ? 1 : 0
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-eip"
    }
  )

  lifecycle {
    prevent_destroy = false
  }
}

# WordPress EC2 Instance
resource "aws_instance" "wordpress" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  
  key_name             = aws_key_pair.wordpress.key_name
  iam_instance_profile = aws_iam_instance_profile.wordpress.name
  
  vpc_security_group_ids = [var.security_group_id]
  subnet_id              = var.subnet_id

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = merge(
      var.tags,
      {
        Name = "${var.project_name}-root-volume"
      }
    )
  }

  user_data = templatefile("${path.module}/../../user-data.sh", {
    wp_db_name             = var.wp_db_name
    wp_db_user             = var.wp_db_user
    wp_db_password         = var.wp_db_password
    mysql_root_password    = var.mysql_root_password
    domain_name            = var.domain_name
    enable_netdata         = var.enable_netdata
    enable_backups         = var.enable_automated_backups
    backup_retention_days  = var.backup_retention_days
  })

  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # Enforce IMDSv2
    http_put_response_hop_limit = 1
  }

  monitoring = true  # Enable detailed monitoring

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-instance"
    }
  )

  lifecycle {
    ignore_changes = [ami]  # Prevent replacement on AMI updates
  }
}

# Associate EIP
resource "aws_eip_association" "wordpress" {
  count         = var.enable_eip ? 1 : 0
  instance_id   = aws_instance.wordpress.id
  allocation_id = aws_eip.wordpress[0].id
}
