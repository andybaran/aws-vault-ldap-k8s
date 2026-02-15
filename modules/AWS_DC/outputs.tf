// THIS IS NOT secure but we need the private key to retrieve the administrator password from AWS
output "private-key" {
  value      = nonsensitive(tls_private_key.rsa-4096-key.private_key_pem)
  depends_on = [time_sleep.wait_for_dc_reboot]
}

// This is the public DNS address of our instance (via Elastic IP)
output "public-dns-address" {
  value      = aws_eip.domain_controller_eip.public_dns
  depends_on = [time_sleep.wait_for_dc_reboot]
}

// Elastic IP public address
output "eip-public-ip" {
  value      = aws_eip.domain_controller_eip.public_ip
  depends_on = [time_sleep.wait_for_dc_reboot]
}

// Private IP address of the domain controller EC2 instance
output "dc-priv-ip" {
  value      = aws_instance.domain_controller.private_ip
  depends_on = [time_sleep.wait_for_dc_reboot]
}

// This is the decrypted administrator password for the EC2 instance
output "password" {
  value      = nonsensitive(local.password)
  depends_on = [time_sleep.wait_for_dc_reboot]
}

// AWS Keypair name
output "aws_keypair_name" {
  value      = aws_key_pair.rdp-key.key_name
  depends_on = [time_sleep.wait_for_dc_reboot]
}

output "static_roles" {
  description = "Test service account usernames and initial passwords for AD integration tests"
  value = {
    for name, pw in random_password.test_user_password : name => {
      username = name
      password = nonsensitive(pw.result)
      dn       = "CN=${name},CN=Users,DC=${join(",DC=", split(".", var.active_directory_domain))}"
    }
  }
  sensitive  = false
  depends_on = [time_sleep.wait_for_dc_reboot]
}