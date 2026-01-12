data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "tls_private_key" "admin_vm_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "admin_vm_key_pair" {
  key_name   = "admin-vm-key-${var.environment}"
  public_key = tls_private_key.admin_vm_key.public_key_openssh
}

resource "aws_security_group" "admin_vm_ssh" {
  name        = "admin-vm-ssh-${var.environment}"
  description = "Allow SSH access to admin VM"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from allowlist"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowlist_ip]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "admin-vm-ssh-${var.environment}"
  }
}

resource "aws_security_group" "admin_vm_internal" {
  name        = "admin-vm-internal-${var.environment}"
  description = "Allow all internal traffic for admin VM"
  vpc_id      = var.vpc_id

  ingress {
    description = "All traffic from self"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "All traffic to anywhere"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "admin-vm-internal-${var.environment}"
  }
}

locals {
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Update system
    dnf update -y

    # Install useful tools for Vault administration
    dnf install -y wget unzip curl jq git

    # Install Vault CLI
    VAULT_VERSION="1.21.2"
    wget https://releases.hashicorp.com/vault/$${VAULT_VERSION}/vault_$${VAULT_VERSION}_linux_amd64.zip
    unzip vault_$${VAULT_VERSION}_linux_amd64.zip
    mv vault /usr/local/bin/
    rm vault_$${VAULT_VERSION}_linux_amd64.zip

    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl

    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    ./aws/install
    rm -rf aws awscliv2.zip

    # Install helm
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # Create welcome message with Vault connection info
    cat > /etc/motd << 'MOTD'
    ================================================================================

    Welcome to the Vault Administration VM

    This instance is configured to administer the Vault cluster.

    Vault API LoadBalancer: ${var.vault_loadbalancer_hostname}:8200
    Vault UI LoadBalancer:  ${var.vault_ui_loadbalancer_hostname}:8200
    Vault Namespace: ${var.vault_namespace}

    Installed tools:
    - vault (Vault CLI)
    - kubectl (Kubernetes CLI)
    - aws (AWS CLI v2)
    - helm (Helm package manager)
    - jq, curl, wget, git

    ================================================================================
    Quick Start - Access Vault via Internal LoadBalancer:
    ================================================================================

    # Connect to Vault API directly via internal NLB (recommended):
      export VAULT_ADDR=http://${var.vault_loadbalancer_hostname}:8200
      vault status

    # Access Vault UI in browser via internal NLB:
      http://${var.vault_ui_loadbalancer_hostname}:8200

    ================================================================================
    Alternative - Access via kubectl port-forward:
    ================================================================================

    # Configure kubectl first:
      aws eks update-kubeconfig --region ${var.region} --name ${var.eks_cluster_name}

    # Port-forward to Vault:
      kubectl port-forward -n ${var.vault_namespace} svc/${var.vault_service_name} 8200:8200 &
      export VAULT_ADDR=http://localhost:8200
      vault status

    ================================================================================
    MOTD

    # Set up ec2-user environment
    cat >> /home/ec2-user/.bashrc << 'BASHRC'

    # Vault environment variables
    export VAULT_NAMESPACE="${var.vault_namespace}"
    export VAULT_SERVICE="${var.vault_service_name}"
    export VAULT_ADDR="http://${var.vault_loadbalancer_hostname}:8200"
    export VAULT_UI_ADDR="http://${var.vault_ui_loadbalancer_hostname}:8200"

    # Helpful aliases
    alias k='kubectl'
    alias v='vault'
    alias kns='kubectl config set-context --current --namespace'

    BASHRC

    chown ec2-user:ec2-user /home/ec2-user/.bashrc
  EOF
}

resource "aws_instance" "admin_vm" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.admin_vm_key_pair.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [
    aws_security_group.admin_vm_ssh.id,
    aws_security_group.admin_vm_internal.id
  ]

  user_data = local.user_data

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  tags = {
    Name = "vault-admin-vm-${var.environment}"
  }
}
