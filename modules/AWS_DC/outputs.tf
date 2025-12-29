// THIS IS NOT secure but we need the private key to retrieve the administrator password from AWS
output "private-key" {
  value = nonsensitive(tls_private_key.rsa-4096-key.private_key_pem)
}

// This is the public DNS address of our instance
output "public-dns-address" {
  value = aws_instance.domain_controller.public_dns
}

// Private IP address of the domain controller EC2 instance
output "dc-priv-ip" {
  value = aws_instance.domain_controller.private_ip
}

// This is the decrypted administrator password for the EC2 instance
output "password" {
  value = nonsensitive(local.password)
}

// AWS Keypair name
output "aws_keypair_name" {
  value = aws_key_pair.rdp-key.key_name
}

// AWS Security Group ID's
output "sec-group-id-list" {
  value = [aws_security_group.allow_all_internal.id, aws_security_group.rdp_ingress.id]
}