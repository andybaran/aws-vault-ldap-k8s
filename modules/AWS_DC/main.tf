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
  key_name   = "${var.prefix}-${var.aws_key_pair_name}"
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


// Create a random string to be used in the user_data script
resource "random_string" "DSRMPassword" {
  length           = 8
  override_special = "." # I've set this explicitly so as to avoid characters such as "$" and "'" being used and requiring unneccesary complexity to our user_data scripts
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}




// Generate random passwords for test service accounts created during post-promotion boot
resource "random_password" "test_user_password" {
  for_each = toset(["svc-rotate-a", "svc-rotate-b", "svc-single", "svc-lib"])

  length           = 16
  override_special = "!@#"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

// Deploy a Windows EC2 instance using the previously created, aws_security_group's, aws_key_pair and use a userdata script to create a windows domain controller
data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"] # Amazon's owner ID for Windows AMIs

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
  vpc_security_group_ids = [aws_security_group.rdp_ingress.id, var.shared_internal_sg_id]
  subnet_id              = var.subnet_id
  key_name               = aws_key_pair.rdp-key.key_name

  root_block_device {
    volume_type           = "gp2"
    volume_size           = var.root_block_device_size
    delete_on_termination = "true"
  }

  user_data_replace_on_change = true

  user_data = <<EOF
                <powershell>
                  # Check if this is a post-promotion reboot (AD DS is running)
                  $ADDSRunning = Get-Service NTDS -ErrorAction SilentlyContinue
                  if ($ADDSRunning -and $ADDSRunning.Status -eq 'Running') {
                    # Post-promotion boot: install AD CS to enable LDAPS on port 636
                    $AdcsFeature = Get-WindowsFeature -Name ADCS-Cert-Authority
                    if (-not $AdcsFeature.Installed) {
                      Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools
                      Install-AdcsCertificationAuthority -CAType EnterpriseRootCA -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" -KeyLength 2048 -HashAlgorithmName SHA256 -ValidityPeriod Years -ValidityPeriodUnits 5 -Force
                      Restart-Service NTDS -Force
                    }

                    # Create test service accounts for integration testing
                    Import-Module ActiveDirectory
                    $testUsers = @{
                      "svc-rotate-a" = "${random_password.test_user_password["svc-rotate-a"].result}"
                      "svc-rotate-b" = "${random_password.test_user_password["svc-rotate-b"].result}"
                      "svc-single"   = "${random_password.test_user_password["svc-single"].result}"
                      "svc-lib"      = "${random_password.test_user_password["svc-lib"].result}"
                    }
                    foreach ($user in $testUsers.GetEnumerator()) {
                      if (-not (Get-ADUser -Filter "sAMAccountName -eq '$($user.Key)'" -ErrorAction SilentlyContinue)) {
                        $secPw = ConvertTo-SecureString $user.Value -AsPlainText -Force
                        New-ADUser -Name $user.Key `
                          -SamAccountName $user.Key `
                          -UserPrincipalName "$($user.Key)@${var.active_directory_domain}" `
                          -AccountPassword $secPw `
                          -Enabled $true `
                          -PasswordNeverExpires $true `
                          -CannotChangePassword $false `
                          -Path "CN=Users,DC=${join(",DC=", split(".", var.active_directory_domain))}"
                      }
                    }
                  } else {
                    # First boot: promote to domain controller
                    $password = ConvertTo-SecureString ${random_string.DSRMPassword.result} -AsPlainText -Force
                    Add-WindowsFeature -name ad-domain-services -IncludeManagementTools
                    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "AuditReceivingNTLMTraffic" -Value 1
                    Install-ADDSForest -CreateDnsDelegation:$false -DomainMode Win2012R2 -DomainName ${var.active_directory_domain} -DomainNetbiosName ${var.active_directory_netbios_name} -ForestMode Win2012R2 -InstallDns:$true -SafeModeAdministratorPassword $password -Force:$true
                  }
                </powershell>
                <persist>true</persist>
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

# Wait for DC reboot after promotion
# The DC reboots after Install-ADDSForest, then installs AD CS and creates
# test users on the second boot. This takes approximately 10 minutes.
resource "time_sleep" "wait_for_dc_reboot" {
  depends_on = [aws_eip.domain_controller_eip]

  create_duration = "10m"
}

locals {
  password = rsadecrypt(aws_instance.domain_controller.password_data, tls_private_key.rsa-4096-key.private_key_pem)
}

