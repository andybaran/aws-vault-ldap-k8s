data "aws_vpc" "default" {
  default = true
}

// Deploy a Windows EC2 instance using the previously created, aws_security_group's, aws_key_pair and use a userdata script to join an Active Directory domain
resource "aws_instance" "member_server" {
  ami                    = var.ami
  instance_type          = var.member_server_instance_type
  vpc_security_group_ids = var.domain_controller_sec_group_id_list
  key_name               = var.domain_controller_aws_keypair_name

  root_block_device {
    volume_type           = "gp2"
    volume_size           = var.root_block_device_size
    delete_on_termination = "true"
  }

  user_data_replace_on_change = true

  user_data = <<EOF
                <powershell>
                  [int]$intix = Get-NetAdapter | % { Process { If ( $_.Status -eq "up" ) { $_.ifIndex } }}
Set-DNSClientServerAddress -interfaceIndex $intix -ServerAddresses ("${var.domain_controller_ip}","127.0.0.1")
$here_string_password = @'
${var.domain_admin_password}
'@
$password = ConvertTo-SecureString $here_string_password -AsPlainText -Force
$username = "mydomain\Administrator" 
$credential = New-Object System.Management.Automation.PSCredential($username,$password)
$server = Resolve-DnsName -Name _ldap._tcp.dc._msdcs.mydomain.local -Type SRV | Where-Object {$_.Type -eq "A"} | Select -ExpandProperty Name
set-item wsman:localhost\client\trustedhosts *.mydomain.local -Force
$s = New-PSSession -ComputerName $server -Credential $credential
Invoke-Command -Session $s -ScriptBlock { $server = Resolve-DnsName -Name _ldap._tcp.dc._msdcs.mydomain.local -Type SRV | Where-Object {$_.Type -eq "A"} | Select -ExpandProperty Name }
Invoke-Command -Session $s -ScriptBlock { New-ADOrganizationalUnit -Name "RDP Member Servers" -Path "DC=mydomain,DC=local" -Server $server }
Invoke-Command -Session $s -ScriptBlock { New-GPO -Name "RDP Settings 01" }
Invoke-Command -Session $s -ScriptBlock { $GPOGuid = Get-gpo -name "RDP Settings 01" | Select -ExpandProperty Id }
Invoke-Command -Session $s -ScriptBlock { Set-GPRegistryValue -Guid $GPOGuid  -Key "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -ValueName "fDenyTSConnections" -Value 0 -Type DWord }
Invoke-Command -Session $s -ScriptBlock { New-GPLink -Guid $GPOGuid -Target "ou=RDP Member Servers,DC=mydomain,DC=local" -LinkEnabled Yes -Enforced Yes }
Remove-PSSession $s
Add-Computer -DomainName "mydomain.local" -OUPath "ou=RDP Member Servers,DC=mydomain,DC=local" -Credential $credential
%{ if var.prevent_NTLMv1 ~}
  Set-ItemProperty  -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\TerminalServerGateway\Config\Core"  -Name EnforceChannelBinding -Value 1 
%{ endif ~}
Restart-Computer -Force
                </powershell>
              EOF
  
  metadata_options {
    http_endpoint          = "enabled"
    instance_metadata_tags = "enabled"
  }
  get_password_data = true
}

locals {
  password = rsadecrypt(aws_instance.member_server.password_data,var.domain_controller_private_key)
}

// This sleep will create a timer of 10 minutes
resource "time_sleep" "wait_2_minutes" {
  depends_on = [ aws_instance.member_server ]
  create_duration = "2m"
}
