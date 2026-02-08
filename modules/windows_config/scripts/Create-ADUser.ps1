# PowerShell script to create vault-demo user in Active Directory
# All dynamic values are passed via environment variables to avoid
# Terraform interpolation issues with special characters in passwords.

$ErrorActionPreference = "Stop"

$ADServer = $env:AD_SERVER
$VaultUser = $env:VAULT_USER
$InitialPassword = $env:INITIAL_PASSWORD
$UserDN = "CN=$VaultUser,CN=Users,DC=mydomain,DC=local"
$MaxRetries = 30
$RetryDelay = 10

Write-Host "==============================================="
Write-Host "AD User Creation Job Starting (PowerShell)"
Write-Host "AD Server: $ADServer"
Write-Host "User: $VaultUser"
Write-Host "User DN: $UserDN"
Write-Host "Method: Native AD PowerShell cmdlets"
Write-Host "==============================================="

# Build credential object from environment variables
$AdminPassword = ConvertTo-SecureString -String $env:ADMIN_PASSWORD -AsPlainText -Force
$AdminUsername = ($env:ADMIN_DN -replace 'CN=([^,]+),.*','$1')
$DomainName = "mydomain"
$Credential = New-Object System.Management.Automation.PSCredential("$DomainName\$AdminUsername", $AdminPassword)

Write-Host "Admin User: $DomainName\$AdminUsername"

# Wait for AD server to be ready
Write-Host "Waiting for AD server to be ready..."
$Connected = $false
for ($i = 1; $i -le $MaxRetries; $i++) {
  try {
    $TestResult = Test-NetConnection -ComputerName $ADServer -Port 389 -InformationLevel Quiet -WarningAction SilentlyContinue
    if ($TestResult) {
      Write-Host "AD server is reachable on port 389"
      $Connected = $true
      break
    }
  } catch {
    # Connection failed, will retry
  }

  if ($i -eq $MaxRetries) {
    Write-Host "ERROR: AD server not reachable after $MaxRetries attempts"
    Write-Host "Network debugging:"
    try { Resolve-DnsName $ADServer } catch { Write-Host "DNS resolution failed" }
    Test-NetConnection -ComputerName $ADServer -Port 389 -InformationLevel Detailed
    exit 1
  }

  Write-Host "Waiting for AD server... (attempt $i/$MaxRetries)"
  Start-Sleep -Seconds $RetryDelay
}

# Additional wait for AD service to be fully initialized
Write-Host "Waiting 10 seconds for AD service to fully initialize..."
Start-Sleep -Seconds 10

# Import Active Directory module
Write-Host "Loading Active Directory PowerShell module..."
try {
  Import-Module ActiveDirectory -ErrorAction Stop
  Write-Host "Active Directory module loaded successfully"
} catch {
  Write-Host "ERROR: Failed to load Active Directory module"
  Write-Host $_.Exception.Message
  exit 1
}

# Test AD authentication
Write-Host "Testing AD authentication..."
try {
  $null = Get-ADDomain -Server $ADServer -Credential $Credential -ErrorAction Stop
  Write-Host "AD authentication successful"
} catch {
  Write-Host "ERROR: AD authentication failed"
  Write-Host $_.Exception.Message
  exit 1
}

# Check if user already exists
Write-Host "Checking if user $VaultUser already exists..."
try {
  $ExistingUser = Get-ADUser -Identity $VaultUser -Server $ADServer -Credential $Credential -ErrorAction SilentlyContinue
  if ($ExistingUser) {
    Write-Host "User $VaultUser already exists - removing for fresh start (demo mode)"
    try {
      Remove-ADUser -Identity $VaultUser -Server $ADServer -Credential $Credential -Confirm:$false -ErrorAction Stop
      Write-Host "Existing user deleted successfully"
      Start-Sleep -Seconds 2
    } catch {
      Write-Host "Warning: Failed to delete existing user"
      Write-Host $_.Exception.Message
    }
  } else {
    Write-Host "User $VaultUser does not exist, proceeding with creation"
  }
} catch {
  Write-Host "User $VaultUser does not exist, proceeding with creation"
}

# Create user with password using splatting
Write-Host "Creating user $VaultUser with password..."
try {
  $SecurePassword = ConvertTo-SecureString -String $InitialPassword -AsPlainText -Force

  $NewUserParams = @{
    Name                  = $VaultUser
    SamAccountName        = $VaultUser
    UserPrincipalName     = "$VaultUser@mydomain.local"
    DisplayName           = "Vault Demo Service Account"
    Description           = "Service account managed by HashiCorp Vault for password rotation demo"
    AccountPassword       = $SecurePassword
    Enabled               = $true
    PasswordNeverExpires  = $false
    ChangePasswordAtLogon = $false
    Server                = $ADServer
    Credential            = $Credential
    Path                  = "CN=Users,DC=mydomain,DC=local"
    ErrorAction           = "Stop"
  }
  New-ADUser @NewUserParams

  Write-Host "User created successfully with password and enabled"
} catch {
  Write-Host "Failed to create user"
  Write-Host $_.Exception.Message
  exit 1
}

# Verify user was created
Write-Host "Verifying user creation..."
try {
  $CreatedUser = Get-ADUser -Identity $VaultUser -Server $ADServer -Credential $Credential -Properties Enabled,PasswordNeverExpires -ErrorAction Stop
  Write-Host "User verification successful"
  Write-Host ("  SamAccountName: " + $CreatedUser.SamAccountName)
  Write-Host ("  DistinguishedName: " + $CreatedUser.DistinguishedName)
  Write-Host ("  Enabled: " + $CreatedUser.Enabled)
  Write-Host ("  PasswordNeverExpires: " + $CreatedUser.PasswordNeverExpires)
} catch {
  Write-Host "Warning: User verification failed"
  Write-Host $_.Exception.Message
}

# Test user authentication
Write-Host "Testing user authentication with new password..."
try {
  $TestPassword = ConvertTo-SecureString -String $InitialPassword -AsPlainText -Force
  $TestCredential = New-Object System.Management.Automation.PSCredential("$DomainName\$VaultUser", $TestPassword)
  $null = Get-ADDomain -Server $ADServer -Credential $TestCredential -ErrorAction Stop
  Write-Host "User authentication successful - password is working"
} catch {
  Write-Host "Warning: User authentication test failed (may need replication time)"
  Write-Host $_.Exception.Message
}

Write-Host "==============================================="
Write-Host "AD User Creation Job Completed Successfully"
Write-Host ("User: " + $VaultUser)
Write-Host ("DN: " + $UserDN)
Write-Host "Note: This password will be rotated by Vault"
Write-Host "==============================================="
