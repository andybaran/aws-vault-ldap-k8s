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
  for_each = toset(["svc-rotate-a", "svc-rotate-b", "svc-rotate-c", "svc-rotate-d", "svc-rotate-e", "svc-rotate-f", "svc-single", "svc-lib"])

  length           = 16
  override_special = "!@#"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

// IAM role granting the DC instance SSM access for remote diagnostic sessions
resource "aws_iam_role" "dc_ssm_role" {
  name = "${var.prefix}-dc-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "dc_ssm_policy" {
  role       = aws_iam_role.dc_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "dc_ssm_profile" {
  name = "${var.prefix}-dc-ssm-profile"
  role = aws_iam_role.dc_ssm_role.name
}

// Security-approved Windows Server 2025 AMI from internal AMI pipeline
// Updated weekly by the security team — always uses most_recent
data "aws_ami" "hc_base_windows_server_2025" {
  most_recent = true
  owners      = ["888995627335"] # hc-ami_prod

  filter {
    name   = "name"
    values = ["hc-base-windows-server-2025-x64-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

// Standard AWS Windows Server 2025 Desktop Experience AMI — used when full_ui = true
// Provides full Windows GUI (Explorer, taskbar, Server Manager) for administration via RDP
data "aws_ami" "windows_2025_full" {
  count       = var.full_ui ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2025-English-Full-Base-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}


resource "aws_instance" "domain_controller" {
  ami                    = var.full_ui ? data.aws_ami.windows_2025_full[0].id : data.aws_ami.hc_base_windows_server_2025.id
  instance_type          = var.domain_controller_instance_type
  vpc_security_group_ids = [aws_security_group.rdp_ingress.id, var.shared_internal_sg_id]
  subnet_id              = var.subnet_id
  key_name               = aws_key_pair.rdp-key.key_name
  iam_instance_profile   = aws_iam_instance_profile.dc_ssm_profile.name

  root_block_device {
    volume_type           = "gp2"
    volume_size           = var.root_block_device_size
    delete_on_termination = "true"
  }

  user_data_replace_on_change = true

  user_data = <<EOF
                <powershell>
                  # Log all output to a transcript file for debugging
                  $logFile = "C:\user_data.log"
                  Start-Transcript -Path $logFile -Append -Force
                  $ErrorActionPreference = "Continue"

                  try {
                    Write-Output "=== User data script started at $(Get-Date -Format o) ==="
                    Write-Output "OS: $((Get-CimInstance Win32_OperatingSystem).Caption)"
                    Write-Output "Hostname: $env:COMPUTERNAME"

                    # Enable WinRM for remote debugging from VPC
                    try {
                      Enable-PSRemoting -Force -SkipNetworkProfileCheck 2>&1
                      Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force 2>&1
                      Write-Output "WinRM enabled successfully"
                    } catch {
                      Write-Output "WinRM setup warning: $_"
                    }

                    # Check if this is a post-promotion reboot (AD DS is running)
                    $ADDSRunning = Get-Service NTDS -ErrorAction SilentlyContinue
                    if ($ADDSRunning -and $ADDSRunning.Status -eq 'Running') {
                      Write-Output "=== Post-promotion boot detected ==="

%{if var.install_adcs}
                      # Install AD CS to enable LDAPS on port 636
                      $AdcsFeature = Get-WindowsFeature -Name ADCS-Cert-Authority
                      Write-Output "ADCS feature state: Installed=$($AdcsFeature.Installed)"
                      if (-not $AdcsFeature.Installed) {
                        Write-Output "Installing ADCS-Cert-Authority..."
                        $result = Install-WindowsFeature -Name ADCS-Cert-Authority -IncludeManagementTools
                        Write-Output "ADCS install result: Success=$($result.Success), RestartNeeded=$($result.RestartNeeded)"

                        Write-Output "Configuring AD CS Enterprise Root CA..."
                        Install-AdcsCertificationAuthority -CAType EnterpriseRootCA -CryptoProviderName "RSA#Microsoft Software Key Storage Provider" -KeyLength 2048 -HashAlgorithmName SHA256 -ValidityPeriod Years -ValidityPeriodUnits 5 -Force 2>&1
                        Restart-Service NTDS -Force
                        Write-Output "AD CS configured and NTDS restarted"

                        # Wait for ADWS to be ready before using AD PowerShell module
                        Write-Output "Waiting for Active Directory Web Services (ADWS) to start..."
                        $timeout = 120; $elapsed = 0
                        do {
                          Start-Sleep 5; $elapsed += 5
                          $adws = Get-Service ADWS -ErrorAction SilentlyContinue
                          Write-Output "ADWS status: $($adws.Status) ($${elapsed}s elapsed)"
                        } while (($adws.Status -ne 'Running') -and ($elapsed -lt $timeout))
                        if ($adws.Status -ne 'Running') {
                          Start-Service ADWS -ErrorAction SilentlyContinue
                          Start-Sleep 10
                        }
                      }
%{else}
                      Write-Output "AD CS installation skipped (install_adcs = false) — LDAPS on port 636 will not be available"
%{endif}

                      # Create test service accounts for integration testing
                      Write-Output "Importing ActiveDirectory module..."
                      Import-Module ActiveDirectory -ErrorAction Stop
                      Write-Output "ActiveDirectory module imported"

                      $testUsers = @{
                        "svc-rotate-a" = "${random_password.test_user_password["svc-rotate-a"].result}"
                        "svc-rotate-b" = "${random_password.test_user_password["svc-rotate-b"].result}"
                        "svc-rotate-c" = "${random_password.test_user_password["svc-rotate-c"].result}"
                        "svc-rotate-d" = "${random_password.test_user_password["svc-rotate-d"].result}"
                        "svc-rotate-e" = "${random_password.test_user_password["svc-rotate-e"].result}"
                        "svc-rotate-f" = "${random_password.test_user_password["svc-rotate-f"].result}"
                        "svc-single"   = "${random_password.test_user_password["svc-single"].result}"
                        "svc-lib"      = "${random_password.test_user_password["svc-lib"].result}"
                      }
                      foreach ($user in $testUsers.GetEnumerator()) {
                        try {
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
                            Write-Output "Created user: $($user.Key)"
                          } else {
                            Write-Output "User already exists: $($user.Key)"
                          }
                        } catch {
                          Write-Output "ERROR creating user $($user.Key): $_"
                        }
                      }
                      Write-Output "=== Post-promotion setup complete ==="

                    } else {
                      Write-Output "=== First boot: promoting to domain controller ==="
%{if var.install_adds}
                      # Check available features
                      Write-Output "Checking AD DS feature availability..."
                      $addsFeature = Get-WindowsFeature -Name AD-Domain-Services
                      Write-Output "AD-Domain-Services: InstallState=$($addsFeature.InstallState), Available=$($addsFeature.Installed -eq $false -and $addsFeature.InstallState -ne 'Removed')"

                      if ($addsFeature.InstallState -eq 'Removed') {
                        Write-Output "ERROR: AD-Domain-Services feature sources removed from this AMI. Attempting install with -Source..."
                      }

                      Write-Output "Installing AD DS role..."
                      $installResult = Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop
                      Write-Output "AD DS install result: Success=$($installResult.Success), RestartNeeded=$($installResult.RestartNeeded), ExitCode=$($installResult.ExitCode)"

                      if (-not $installResult.Success) {
                        Write-Output "FATAL: AD DS installation failed!"
                        Stop-Transcript
                        exit 1
                      }

                      Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" -Name "AuditReceivingNTLMTraffic" -Value 1

                      # Disable Defender real-time protection during AD DS promotion to prevent
                      # JET_errFileNotFound -1032 caused by Defender locking ntds.dit during creation.
                      # Defender re-enables automatically after the post-promotion reboot.
                      Write-Output "Disabling Defender real-time protection for AD DS promotion..."
                      Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
                      # Start-Sleep -Seconds 5

                      Write-Output "Promoting to domain controller (domain: ${var.active_directory_domain})..."
                      $password = ConvertTo-SecureString ${random_string.DSRMPassword.result} -AsPlainText -Force
                      Install-ADDSForest -CreateDnsDelegation:$false -DomainMode WinThreshold -DomainName ${var.active_directory_domain} -DomainNetbiosName ${var.active_directory_netbios_name} -ForestMode WinThreshold -InstallDns:$true -SafeModeAdministratorPassword $password -Force:$true 2>&1
                      Write-Output "Install-ADDSForest completed (system will reboot automatically)"
%{else}
                      Write-Output "AD DS installation skipped (install_adds = false) — running as plain Windows Server"
%{endif}
                    }
                  } catch {
                    Write-Output "FATAL ERROR: $_"
                    Write-Output $_.ScriptStackTrace
                  } finally {
                    Stop-Transcript
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
# test users on the second boot. Duration is adjusted based on enabled features:
#   install_adds=false → 3m  (plain Windows boot only)
#   install_adds=true, install_adcs=false → 7m  (AD DS promote + reboot, no ADCS restart)
#   install_adds=true, install_adcs=true  → 10m (full setup with ADCS + NTDS restart)
resource "time_sleep" "wait_for_dc_reboot" {
  depends_on = [aws_eip.domain_controller_eip]

  triggers = {
    instance_id = aws_instance.domain_controller.id
  }

  create_duration = local.dc_wait_duration
}

locals {
  password = rsadecrypt(aws_instance.domain_controller.password_data, tls_private_key.rsa-4096-key.private_key_pem)

  dc_wait_duration = !var.install_adds ? "3m" : (!var.install_adcs ? "7m" : "10m")
}

