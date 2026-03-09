// THIS IS NOT secure but we need the private key to retrieve the administrator password from AWS
output "private-key" {
  value = var.enabled ? nonsensitive(tls_private_key.rsa-4096-key[0].private_key_pem) : ""
}

// This is the public DNS address of our instance (via Elastic IP)
output "public-dns-address" {
  value = var.enabled ? aws_eip.domain_controller_eip[0].public_dns : ""
}

// Elastic IP public address
output "eip-public-ip" {
  value = var.enabled ? aws_eip.domain_controller_eip[0].public_ip : ""
}

// Private IP address of the domain controller EC2 instance
output "dc-priv-ip" {
  value = var.enabled ? aws_instance.domain_controller[0].private_ip : ""
}

// This is the decrypted administrator password for the EC2 instance
output "password" {
  value = var.enabled ? nonsensitive(local.password) : ""
}

// AWS Keypair name
output "aws_keypair_name" {
  value = var.enabled ? aws_key_pair.rdp-key[0].key_name : ""
}

output "static_roles" {
  description = "Test service account usernames and initial passwords for AD integration tests"
  value = var.enabled ? {
    for name, pw in random_password.test_user_password : name => {
      username = name
      password = nonsensitive(pw.result)
      dn       = "CN=${name},CN=Users,DC=${join(",DC=", split(".", var.active_directory_domain))}"
    }
  } : {}
  sensitive = false
}