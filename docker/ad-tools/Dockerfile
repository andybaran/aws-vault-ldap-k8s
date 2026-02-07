# Windows Server Core image with RSAT-AD-PowerShell pre-installed
# Used by the create-ad-user Kubernetes job to create AD users via PowerShell cmdlets
FROM mcr.microsoft.com/windows/servercore:ltsc2022

# Install RSAT Active Directory PowerShell module at build time
# This avoids the 15-30 minute Install-WindowsFeature delay at runtime
RUN powershell -Command "Install-WindowsFeature -Name RSAT-AD-PowerShell -ErrorAction Stop"

# Verify the module is available
RUN powershell -Command "Import-Module ActiveDirectory -ErrorAction Stop; Get-Command New-ADUser"
