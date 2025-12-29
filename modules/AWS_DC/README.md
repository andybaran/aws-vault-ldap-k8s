# Domain Controller in AWS Module

This Terraform code will deploy a single Windows Domain Controller in AWS.
The domain controller can then be accessed using RDP from the address(es) specified in `allowlist_ip`.

## Required Input Variables

| Variable Name     | Description                                                                                                   |
| ----------------- | --------------                                                                                                |
| allowlist_ip      | Your public IP address. This is used to configure AWS firewall rules to allow RDP connectivity to the machine |

## Outputs

| Variable Name           | Description                                             |
| -----------------       | --------------                                          |
| private-key             | Private key used to decrypt the administrator password  |
| public-dns-address      | Public DNS Address for the EC2 instance                 |
| password                | Administrator password for the EC2 instance             |

## Scripts

This code is primarily basic Terraform to create a Windows based EC2 instance and firewall rules to all access to it.  Besides Terraform, there is a snippet of PowerShell used to configure Domain Controller services on the EC2 instance using some values from our Terraform configs:

```powershell
$password = ConvertTo-SecureString ${random_string.DSRMPassword.result} -AsPlainText -Force

Add-WindowsFeature -name ad-domain-services -IncludeManagementTools

Install-ADDSForest -CreateDnsDelegation:$false -DomainMode Win2012R2 -DomainName ${var.active_directory_domain} -DomainNetbiosName ${var.active_directory_netbios_name} -ForestMode Win2012R2 -InstallDns:$true -SafeModeAdministratorPassword $password -Force:$true
```

For the sake of readability, I've added empty lines between each line above that do no appear in the code.

1. Terraform used the random_string provider to generate a password.  Here we convert this string to a PowerShell SecureString so it can be used as input for a later PowerShell cmdlet.
2. The Add-WindowsFeature cmdlet is used to add the bits necessary to install Active Directory Domain Services and the corresponding management tools.  While not strictly required for recent versions of Windows, the AWS AMI does require we run this. 
3. Use the [Install-ADDSForest cmdlet](https://learn.microsoft.com/en-us/powershell/module/addsdeployment/install-addsforest?view=windowsserver2022-ps) to use the now added bits to install a new Active Directory Forest with the following arguments.  An Active Directory Forest is the top most logical unit in Active Directory and can contain one or many Active Directory Domains.  Here we will only be working with a single Active Directory Domain.

| Flag                          | Value                    | Description                                                                                                                                                                                                                                         |
| -----------------             | --------------           | --------------                                                                                                                                                                                                                                      |
| CreateDnsDelegation           | $false                   | DNS is a key component to Active Directory.  By not creating delegation we are telling the cmdlet to configure this server as a DNS server as well. We have seen errors when not explicitly setting this to false in the past so are doing so here. |
| DomainMode                    | Win2012R2                | As Active Directory has evolved new features that are not backward compatible with previous versions have been introduced.  This compatibility mode starts us at a version that is very commonly used in enterprises.                               |
| DomainName                    | mydomain.local           | This is simply the DNS name used by the domain which is appended to usernames for logging in. For example, Administrator becomes Administrator@mydomain.local                                                                                       |
| DomainNetbiosName             | mydomain                 | This is a historical requirement of Active Directory that is most commonly equal to the first 8 characters of the DomainName.                                                                                                                       |
| ForestMode                    | Win2012R2                | An Active Directory Forest is a logical grouping of Active Directory Domains and can be set to a different compatibility mode than the domains within.  This compatibility mode starts us at a version that is very commonly used in enterprises.   |
| SafeModeAdministratorPassword | Randomly generated by TF | This is used for troubleshooting in Safe Mode. Very likely you are better off simply re-deploying than trying to troubleshoot in Safe Mode.                                                                                                         |
