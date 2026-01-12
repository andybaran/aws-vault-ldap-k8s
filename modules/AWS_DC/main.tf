terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}


data "aws_vpc" "default" {
  #default = true
  id = var.vpc_id
}

// We need a keypair to obtain the local administrator credentials to an AWS Windows based EC2 instance. So we generate it locally here
resource "tls_private_key" "rsa-4096-key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

// Create an AWS keypair using the keypair we just generated
resource "aws_key_pair" "rdp-key" {
  key_name = "${var.prefix}-${var.aws_key_pair_name}"
  public_key = tls_private_key.rsa-4096-key.public_key_openssh
}

// Create an AWS security group to allow RDP traffic in and out to from IP's on the allowlist.
// We also allow ingress to port 88, where the Kerberos KDC is running.
resource "aws_security_group" "rdp_ingress" {
  name   = "${var.prefix}-rdp-ingress"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.allowlist_ip]
  }

    ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "udp"
    cidr_blocks = [var.allowlist_ip]
  }
  
  ingress {
    from_port   = 88
    to_port     = 88
    protocol    = "tcp"
    cidr_blocks = [var.allowlist_ip]
  }
  
  ingress {
    from_port   = 88
    to_port     = 88
    protocol    = "udp"
    cidr_blocks = [var.allowlist_ip]
  }
}

// Create an AWS security group to allow all traffic originating from the default vpc
resource "aws_security_group" "allow_all_internal" {
  name   = "${var.prefix}-allow-all-internal"
  vpc_id = var.vpc_id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// Create a random string to be used in the user_data script
resource "random_string" "DSRMPassword" {
  length = 8
  override_special = "." # I've set this explicitly so as to avoid characters such as "$" and "'" being used and requiring unneccesary complexity to our user_data scripts
  min_lower = 1
  min_upper = 1
  min_numeric = 1
  min_special = 1
}




// Deploy a Windows EC2 instance using the previously created, aws_security_group's, aws_key_pair and use a userdata script to create a windows domain controller
data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]  # Amazon's owner ID for Windows AMIs

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


resource "aws_instance" "domain_controller" {
  ami                    = data.aws_ami.windows_2022.id
  instance_type          = var.domain_controller_instance_type
  vpc_security_group_ids = [aws_security_group.rdp_ingress.id, aws_security_group.allow_all_internal.id]
  subnet_id = var.subnet_id
  key_name               = aws_key_pair.rdp-key.key_name

  root_block_device {
    volume_type           = "gp2"
    volume_size           = var.root_block_device_size
    delete_on_termination = "true"
  }

  user_data_replace_on_change = true

  user_data = <<EOF
                <powershell>
                  $password = ConvertTo-SecureString ${random_string.DSRMPassword.result} -AsPlainText -Force
                  Add-WindowsFeature -name ad-domain-services -IncludeManagementTools
                  Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "AuditReceivingNTLMTraffic" -Value 1
                  %{ if var.only_ntlmv2 ~}
                    Set-ItemProperty  -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"  -Name LMCompatibilityLevel -Value 5 
                  %{ endif ~}
                  %{ if var.only_kerberos ~}
                    Set-ItemProperty  -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0"  -Name RestrictSendingNTLMTraffic -Value 2 
                    Set-ItemProperty  -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0"  -Name RestrictReceivingNTLMTraffic -Value 2 
                  %{ endif ~}    
                  Install-ADDSForest -CreateDnsDelegation:$false -DomainMode Win2012R2 -DomainName ${var.active_directory_domain} -DomainNetbiosName ${var.active_directory_netbios_name} -ForestMode Win2012R2 -InstallDns:$true -SafeModeAdministratorPassword $password -Force:$true
                </powershell>
              EOF
  
  metadata_options {
    http_endpoint          = "enabled"
    instance_metadata_tags = "enabled"
  }
  get_password_data = true
}

# Elastic IP for domain controller
resource "aws_eip" "domain_controller_eip" {
  domain   = "vpc"
  instance = aws_instance.domain_controller.id

  tags = {
    Name = "${var.prefix}-dc-eip"
  }

  depends_on = [aws_instance.domain_controller]
}

locals {
  password = rsadecrypt(aws_instance.domain_controller.password_data,tls_private_key.rsa-4096-key.private_key_pem)
}

#// This sleep will create a timer of 10 minutes
#resource "time_sleep" "wait_10_minutes" {
#  depends_on = [ aws_instance.domain_controller ]
#  create_duration = "10m"
#}
