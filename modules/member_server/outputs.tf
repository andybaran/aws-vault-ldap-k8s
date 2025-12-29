
// This is the public DNS address of our instance
output "public-dns-address" {
  value = aws_instance.member_server.public_dns
}

// This is the decrypted administrator password for the EC2 instance
output "password" {
  value = local.password
}
