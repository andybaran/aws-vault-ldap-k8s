# Domain Member Server in AWS Module

This Terraform code will deploy a single Windows Domain Controller in AWS.
The domain controller can then be accessed using RDP from the address(es) specified in `allowlist_ip`.

## Required Input Variables



| Variable Name                       | Description                                                                                                                                                       |
| -------------------------------     | --------------------------------------------------------                                                                                                          |
| domain_admin_password               | The Active Directory domain adminstrator password that we will use to join this machine to the domain.                                                            |
| domain_controller_ip                | The IP of an Active Directory domain controller                                                                                                                   |
| domain_controller_aws_keypair_name  | AWS Keypair resource                                                                                                                                              |
| domain_controller_private_key       | Private Key for use with the aws_keypair which stores a corresponding public key.  Used to retrieve the local administrator password of this machine.             |
| domain_controller_sec_group_id_list | List of network security group ID's used for that domain controller belongs to.  This simplifies setup by making all machines have the same traffic rules applied.|

## Outputs

| Variable Name           | Description                                             |
| -----------------       | --------------                                          |
| public-dns-address      | Public DNS Address for the EC2 instance                 |
| password                | Administrator password for the EC2 instance             |

## Scripts

This code is primarily basic Terraform to create a Windows based EC2 instance and firewall rules to all access to it.  Besides Terraform, there is a snippet of PowerShell used to join the instance to an Active Directory domain using some values from our Terraform configs and configure a Group Policy Object (GPO) in the domain.

```powershell
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

Restart-Computer -Force
```

For the sake of readability, I've added empty lines between each line above that do no appear in the code.

1. Get a list of all network adapters currently in use so we change their DNS server settings.
2. Set the primary DNS server on each network adapter in the list to be the internal IPv4 address of our domain controller.  This will allow us to join the Active Directory domain.
3. Our domain adminstrator password can contain special characters so store it in heredoc format in the variable `$here_string_password`.
4. Store our heredoc formatted domain administrator password as a powershell secure string in the variable `$password`.  We will use it later for authentication.
5. Store our Active Directory domain administrator username in the variable `$username`.
6. Create a PSCredential object named `$credential` containing our username and password.  This will be passed to powershell cmdlets which require authentication.
7. To avoid further security related complexity involved in Powershell, we need to connect to our domain controller using it's hostname (as set in the Windows OS) . This command retrieves that hostname and stores it in the variable `$server`.
8. Create a new PowerShell remote session on our domain controller (`$server`) using our username and password stored in `$credentia`l`.
9. I found that some commands work best when the `-Server` flag is specified and given the value of the servers Windows hostname.  We do the same as we did in Step 7 to store that here. This can be simplified in the future by simply passing the variable previously created in step 7 to the invoked command.
10. Use the New-ADOrganizationalUnit cmdlet to create an Active Directory Organizational Unit (OU).  Later we will link a Group Policy Object (GPO) to the OU so that all Computer accounts in that OU recieve the settings it enforces.
11. Create a new Group Policy Object using the New-GPO cmdlet.
12. Retrieve the GUID of the GPO created in the previous step as we will need to reference it later on.
13. Using the GUID retrieved in the previous step, configure the setting `fDenyTSConnections` to be `0`.  By setting this to 0 we are allowing TS connections.
14. Again, using the GUID, link the GPO to the OU.
15. Remove/destory/close the remote PowerShell session.
16. Join the member server to the domain and place it in the OU we created in step 10 so that the GPO settings are enforced.
17. Restart the member server.
                                                                                                       |
